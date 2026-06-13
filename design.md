---
name: Wikibase Data Services
description: Visual identity for the GitHub Pages site of lucamauri's open-source projects. Dark, utilitarian aesthetic inspired by developer tooling documentation sites (Traefik, Caddy, MinIO). Precision and reliability over decoration.
colors:
  primary: "#e6edf3"
  secondary: "#7d8590"
  background: "#0d1117"
  background-card: "#161b22"
  background-subtle: "#1c2330"
  accent: "#58a6ff"
  accent-dim: "#1f3a5f"
  border: "#2d3748"
  border-hi: "#3d4f6b"
  green: "#3fb950"
  green-dim: "#1a3625"
  amber: "#d29922"
typography:
  display:
    fontFamily: IBM Plex Sans
    fontSize: 3rem
    fontWeight: 300
    lineHeight: 1.2
    letterSpacing: -0.02em
  h2:
    fontFamily: IBM Plex Sans
    fontSize: 1.6rem
    fontWeight: 400
    lineHeight: 1.3
  body:
    fontFamily: IBM Plex Sans
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.65
  body-muted:
    fontFamily: IBM Plex Sans
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.7
  small:
    fontFamily: IBM Plex Sans
    fontSize: 0.875rem
    fontWeight: 400
    lineHeight: 1.55
  label-caps:
    fontFamily: IBM Plex Mono
    fontSize: 0.72rem
    fontWeight: 400
    letterSpacing: 0.12em
  mono:
    fontFamily: IBM Plex Mono
    fontSize: 0.82rem
    fontWeight: 400
    lineHeight: 2
rounded:
  sm: 4px
  md: 6px
  lg: 10px
  pill: 999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 64px
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.background}"
    rounded: "{rounded.md}"
    padding: 10px 22px
    typography: "{typography.small}"
  button-primary-hover:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.background}"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
    padding: 10px 22px
  button-secondary-hover:
    backgroundColor: "{colors.accent-dim}"
    textColor: "{colors.primary}"
  nav-link:
    backgroundColor: "transparent"
    textColor: "{colors.secondary}"
  nav-link-hover:
    textColor: "{colors.primary}"
  card:
    backgroundColor: "{colors.background-card}"
    rounded: "{rounded.lg}"
  card-hover:
    backgroundColor: "{colors.background-subtle}"
  code-inline:
    backgroundColor: "{colors.background-subtle}"
    textColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    padding: 1px 6px
  badge-pill:
    backgroundColor: "transparent"
    textColor: "{colors.secondary}"
    rounded: "{rounded.pill}"
    padding: 3px 10px
---

## Overview

Architectural Minimalism for developer tooling. The UI evokes precision and reliability — the visual language of infrastructure documentation rather than consumer software. Everything is purposeful; nothing is decorative.

The palette is almost entirely dark neutrals drawn from GitHub's own dark theme, with a single blue accent (`#58a6ff`) for interactive elements and a green status indicator (`#3fb950`) for live/healthy signals. Amber (`#d29922`) appears only for the Elasticsearch service icon, encoding a semantic meaning (search/index) rather than decoration.

This identity is intentionally generic enough to apply to any open-source infrastructure or developer tooling project by Luca Mauri.

## Colors

The palette has three layers and one accent.

- **Background (`#0d1117`):** Deep page background. Matches GitHub's dark mode so the site feels native when linked from a GitHub repo.
- **Background-card (`#161b22`):** Raised surfaces — service cards, code blocks, doc link tiles.
- **Background-subtle (`#1c2330`):** Hover state for cards. One step lighter than card.
- **Primary (`#e6edf3`):** Main text. High contrast on dark backgrounds, never pure white.
- **Secondary (`#7d8590`):** Muted text — descriptions, metadata, nav links at rest. Use for content that is present but not the focus.
- **Accent (`#58a6ff`):** The sole interactive color. All links, buttons, and hover border highlights use this. Never use it decoratively.
- **Accent-dim (`#1f3a5f`):** Accent background for hover states. Pair with accent borders.
- **Border (`#2d3748`):** Default border for all cards, inputs, and dividers.
- **Border-hi (`#3d4f6b`):** Elevated border for buttons and emphasized containers.
- **Green (`#3fb950`):** Status indicator only. Signals "running", "healthy", "live". The pulsing dot in the nav brand uses this with a matching box-shadow glow.
- **Amber (`#d29922`):** Reserved for the Elasticsearch service card icon. Do not use elsewhere unless encoding the same semantic (search/indexing).

## Typography

Two typefaces only, both from the IBM Plex family — chosen for their technical character and excellent monospace/sans pairing.

- **IBM Plex Sans** — all prose, headings, UI labels, and buttons. The `display` style (hero h1) uses weight 300 to feel architectural rather than heavy. Section h2 uses weight 400.
- **IBM Plex Mono** — all code, all label-caps section eyebrows, the nav brand, the architecture diagram, and the quick start block. The monospace face is a signal: "this is technical content".

Label-caps (`font-size: 0.72rem`, `letter-spacing: 0.12em`, `text-transform: uppercase`) appear above sections and inside code blocks as section markers. They are always in IBM Plex Mono and always in the secondary (muted) color.

Never use font weights above 500. Weight 300 for display, 400 for body, 500 for emphasis and button labels only.

## Layout

Single-column centered layout. `max-width: 860px` container with `2rem` horizontal padding. The constraint keeps line lengths readable and the content feeling deliberate rather than stretched.

Sticky navigation with `backdrop-filter: blur(8px)` and slight transparency — the one visual effect permitted, because it serves a functional purpose (orientation while scrolling).

Sections are separated by `1px solid var(--border)` horizontal rules. No card shadows; borders carry all the depth.

Grids use `repeat(auto-fit, minmax(Npx, 1fr))` so they reflow gracefully on narrow viewports without media query breakpoints.

## Elevation & Depth

No shadows. No gradients. Depth is expressed through background color progression:

```
page background (#0d1117) → card (#161b22) → hover (#1c2330)
```

Each step is visually distinct but subtle. The hover state is the only animation — a `background` transition at `0.15s` ease.

Border highlights (accent color on hover) replace the shadow elevation pattern common in light-mode design systems.

## Shapes

Consistent radius scale with clear intent:

- `4px` — inline code only
- `6px` — buttons, small tiles, requirement list items
- `10px` — cards and major containers (service grid, arch box, quickstart block)
- `999px` — the status badge pill in the footer only

No other border-radius values. Do not round elements that use a single-sided border accent.

## Components

### Navigation

Sticky top bar. Brand on the left (IBM Plex Mono, the green status dot, weight 500). Nav links on the right in secondary color, transitioning to primary on hover. The GitHub button has a `border-hi` border at rest, transitioning to accent border + accent-dim background on hover.

### Hero

Eyebrow label in label-caps style + accent color above the h1. H1 in display style (weight 300, `clamp(2rem, 5vw, 3rem)`). Lead paragraph in body-muted color, max-width 600px. Two action buttons (primary + secondary) in a flex row. The quick start block below the buttons is a `background-card` panel with a monospace code block inside — syntax colored with accent (commands) and secondary (comments).

### Service cards

Six cards in a CSS grid (`minmax(240px, 1fr)`), separated by `1px` gaps on a border-color background — creating the illusion of a unified grid with internal dividers. Each card has a 36px icon container (colored border matching the service's semantic color), an h3, an image name in IBM Plex Mono secondary, and a prose description.

### Architecture diagram

A `background-card` box with IBM Plex Mono content rendered as a literal ASCII diagram. Color classes: `hl` (primary text for Apache/key nodes), `ac` (accent for Traefik), `gr` (green for container endpoints), `am` (amber for Anubis). All other text inherits the muted secondary color.

### Doc link tiles

Eight tiles in a `minmax(200px, 1fr)` grid. Each tile has a title (primary color, weight 500) and a one-line description (secondary color, 0.78rem). On hover: accent border + accent-dim background. No icons — the text carries the meaning.

### Status badge

Footer-right. Pill shape (`999px` radius), border-color border, secondary text in IBM Plex Mono. A 6px green circle inside signals production readiness.

## Do's and Don'ts

**Do:**
- Use IBM Plex Mono for all code, eyebrows, labels, and the nav brand
- Use the accent color exclusively for interactive elements and their hover states
- Keep the background progression strict: page → card → hover, never mixing levels
- Use `1px solid var(--border)` for all dividers and card borders
- Animate only `background` and `border-color` transitions, at `0.15s`

**Don't:**
- Add gradients, drop shadows, blur (except the nav backdrop), or glow effects
- Use font weights above 500 anywhere
- Use the green color for anything other than a live/healthy status signal
- Use the amber color for anything other than the Elasticsearch service
- Add decorative icons or illustrations — SVG icons in service cards must encode meaning, not decoration
- Use more than two typefaces or import fonts beyond IBM Plex Sans and IBM Plex Mono