#!/usr/bin/env node
// Render a mermaid diagram to PNG with mermaid.js in headless Chrome.
//
// usage: node headless-chrome-render.mjs --mermaid <mermaid.min.js> [--mermaid <fallback.js> ...] --puppeteer <dir>
//          -i <in.mmd> -o <out.png> [--width <px>] [--height <px>] [--theme <name>] [--config <json>]
//          [--background <css color>] [--classic-colors true]
//
// Each --mermaid is tried in order and the first that renders wins; when all fail, the last error is reported.
// Every version is initialized with the same options object, like gh-markdown-preview: mermaid 10 writes its resolved
// theme variables into it, so a later fallback inherits the earlier version's colors.
//
// Without --width/--height the PNG is the diagram's natural size; with both, the diagram is scaled to fit them.

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { join } from "node:path";

function parseArgs(argv) {
  const alias = { i: "input", o: "output" };
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--?/, "");
    const name = alias[key] || key;
    const value = argv[++i];
    if (name === "mermaid") {
      (args.mermaid ||= []).push(value);
    } else {
      args[name] = value;
    }
  }
  return args;
}

// mermaid's parse errors span 4 lines (header, source excerpt, caret, expected tokens); fold them into one line
// with the useful part first, since the inline error shows only the first line
function oneLine(msg) {
  const lines = String(msg).split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const head = lines[0] && lines[0].match(/^(Parse|Lexical) error on line (\d+)[:.]?\s*(.*)$/);
  if (!head) return lines.join(" ");
  const excerpt = lines.find((l, i) => i > 0 && !/^-*\^$/.test(l) && !/^Expecting /.test(l));
  const expecting = lines.find((l) => /^Expecting /.test(l));
  const got = expecting && expecting.match(/got '([^']*)'\s*$/);
  const parts = [`${head[1]} error on line ${head[2]}:`];
  if (head[3]) parts.push(head[3]);
  if (got) parts.push(`unexpected '${got[1]}'`);
  if (excerpt) parts.push(`near "${excerpt}"`);
  if (expecting) parts.push(`(${expecting.replace(/,?\s*got '[^']*'\s*$/, "")})`);
  return parts.join(" ");
}

function fail(msg) {
  process.stderr.write(String(msg).trim() + "\n");
  process.exit(1);
}

async function loadPuppeteer(dir) {
  const bases = [dir && join(dir, "package.json"), dir && join(dir, "node_modules", "_"), import.meta.url].filter(Boolean);
  for (const base of bases) {
    try {
      const resolved = createRequire(base).resolve("puppeteer");
      const mod = await import(pathToFileURL(resolved).href);
      return mod.default || mod;
    } catch {}
  }
  fail("puppeteer not found (install @mermaid-js/mermaid-cli or set headless_chrome.puppeteer)");
}

// mermaid 10's dark theme colors where mermaid 11's differ (blue #81B1DB borders instead of grey #ccc), the look of
// markdown-preview.nvim and gh-markdown-preview; applied with --classic-colors
const CLASSIC_DARK = {
  border1: "#81B1DB",
  nodeBorder: "#81B1DB",
  actorBorder: "#81B1DB",
  actorLineColor: "lightgrey",
  labelBoxBorderColor: "#81B1DB",
  activationBorderColor: "#81B1DB",
  compositeBorder: "#81B1DB",
  taskTextDarkColor: "hsl(28.5714285714, 17.3553719008%, 86.2745098039%)",
  pieTitleTextColor: "hsl(28.5714285714, 17.3553719008%, 86.2745098039%)",
  pieLegendTextColor: "hsl(28.5714285714, 17.3553719008%, 86.2745098039%)",
};

// mermaid-viewer themes -> mermaid.js themes
const THEMES = { default: "default", dark: "dark", forest: "forest", neutral: "neutral", modern: "default", base: "base" };

const args = parseArgs(process.argv.slice(2));
if (!args.mermaid || !args.input || !args.output) {
  fail("usage: headless-chrome-render.mjs --mermaid <mermaid.min.js> -i <input> -o <output> [--puppeteer <dir>]");
}

const source = readFileSync(args.input, "utf8");
const theme = THEMES[args.theme] || args.theme || "default";
const userConfig = args.config ? JSON.parse(args.config) : {};
if (args["classic-colors"] === "true" && theme === "dark") {
  userConfig.themeVariables = { ...CLASSIC_DARK, ...(userConfig.themeVariables || {}) };
}

const puppeteer = await loadPuppeteer(args.puppeteer);
// chrome-headless-shell starts ~3x faster than full headless Chrome; fall back when it isn't downloaded
const launchArgs = ["--no-sandbox", "--disable-gpu"];
let browser;
try {
  browser = await puppeteer.launch({ headless: "shell", args: launchArgs });
} catch {
  browser = await puppeteer.launch({ headless: true, args: launchArgs });
}

// Load one more mermaid.js into the page and render with it; leaves the page showing the diagram at its natural size
async function renderWith(page, mermaidJs, attempt) {
  await page.addScriptTag({ path: mermaidJs });

  return page.evaluate(
    async ({ source, theme, userConfig, background, id }) => {
      // same initialization as markdown-preview.nvim: mermaid.initialize({ theme, ...g:mkdp_preview_options.maid }),
      // with one options object shared by every version (see the header)
      window.mermaidViewerOptions ||= { theme, ...userConfig, startOnLoad: false };
      mermaid.initialize(window.mermaidViewerOptions);
      let svg;
      try {
        await mermaid.parse(source);
        ({ svg } = await mermaid.render(id, source));
      } catch (e) {
        return { error: (e && (e.str || e.message)) || String(e) };
      } finally {
        // mermaid leaves its temporary or error element appended to <body>
        document.getElementById("d" + id)?.remove();
      }
      const c = document.getElementById("c");
      c.innerHTML = svg;
      const el = c.querySelector("svg");
      const vb = el.viewBox && el.viewBox.baseVal;
      const box = el.getBoundingClientRect();
      const w = Math.ceil(vb && vb.width ? vb.width : box.width);
      const h = Math.ceil(vb && vb.height ? vb.height : box.height);
      el.style.maxWidth = "none";
      el.setAttribute("width", w);
      el.setAttribute("height", h);
      const cfg = mermaid.mermaidAPI.getConfig();
      const bg = background || (cfg.themeVariables && cfg.themeVariables.background) || "white";
      document.body.style.background = bg;
      c.style.background = bg;
      return { w, h };
    },
    { source, theme, userConfig, background: args.background, id: "mermaid-viewer-diagram-" + attempt }
  );
}

try {
  const page = await browser.newPage();
  await page.setContent(
    '<!doctype html><html><head><style>html,body{margin:0;padding:0}#c{display:inline-block}</style></head>' +
      '<body><div id="c"></div></body></html>'
  );
  let result;
  for (const [attempt, mermaidJs] of args.mermaid.entries()) {
    result = await renderWith(page, mermaidJs, attempt);
    if (!result.error) break;
  }

  if (result.error) fail(oneLine(result.error));

  const { w, h } = result;
  let scale = 1;
  if (args.width && args.height) {
    scale = Math.min(Number(args.width) / w, Number(args.height) / h);
  }
  await page.setViewport({ width: w, height: h, deviceScaleFactor: scale });
  await page.screenshot({ path: args.output, type: "png", clip: { x: 0, y: 0, width: w, height: h } });
} catch (e) {
  fail(e && e.stack ? e.stack : e);
} finally {
  await browser.close();
}
