# Architecture Overview

This document describes the mermaid-viewer.nvim architecture.

## Plugin Flow

```mermaid
flowchart TD
    A[User runs :MermaidView] --> B[Extract source]
    B --> C[Render via mmdr]
    C --> D[Display via Kitty protocol]
    D --> E[User interacts]
    E -->|zoom/pan| D
    E -->|close| F[Cleanup]
```

## Module Dependencies

```mermaid
graph LR
    init --> source
    init --> render
    init --> viewer
    init --> display
    init --> navigation
    init --> debounce
    init --> state
    init --> temp
    display --> kitty
    display --> viewer
    display --> state
    navigation --> display
    navigation --> render
    navigation --> source
    render --> config
    debounce --> config
```

Some text between diagrams to test cursor detection.

## Zoom State Machine

```mermaid
stateDiagram-v2
    [*] --> Fit
    Fit --> Zoomed: +
    Zoomed --> Fit: 0
    Zoomed --> Zoomed: +/-
```
