---
paths:
  - "**/*.{tsx,jsx,vue,svelte,css,scss,html}"
---

# frontend.md

Visual identity and UI rules are user-defined: apply them as written. Framework, libraries, component layout and file structure stay engineering decisions per `rules/rules.md` "How to decide".

## Identity

- The visual identity (logos, brand color values, fonts, type scale, radii) is user-defined and comes from the custom layer (`rules/rules.md` "Custom layer"), loaded with this file. A request naming another brand (e.g. a client's), or no identity loaded: ask for its colors, fonts and logo files in intake; record them in that project's `docs/` and apply the rest of this file unchanged.
- NEVER redraw, recolor, stretch or crop a logo, unless the identity allows it.

## Colors

- Three token layers: brand (the identity's values) → semantic (background, foreground, card, primary, muted, border, ring, chart-n, sidebar) → components. Components use semantic tokens only; NEVER a raw color value in a component.
- Status color ALWAYS with icon and text; NEVER color alone.
- Text contrast >= 4.5:1, large text and UI parts >= 3:1. A color below 3:1 on its background is used only as a fill with a separator or glyph, never as a bare line or icon. A new pair: measure before use.
- Theme follows the operating system by default. The user can switch between system, dark and light; the choice persists. Dark uses the identity's dark values; check contrast on both backgrounds before shipping. Exception: a game has one UI, its own, with no theme and no switch; check contrast on it.
- Illustration or game art: before showing it, MUST look at it at final screen size and check that each figure separates from its background, because plates that passed a numeric tone check were rejected for figures blending into the dark.

## Shape and type

- Headings through one heading-font token, so the font can change in one place. Fonts self-hosted.
- Sizes in `rem`; NEVER `vw` or `clamp()` with `vw` for text. Form inputs 16 px on phones.
- Numbers in tabular figures; ids, endpoints and event types in monospace; long ids break only after `.`, `/` or `-`.
- Spacing between items by gap, not margins.

## Behavior

- Accessibility target WCAG 2.2 AA (a target, not a conformance claim; list what was not verified).
- Mobile first. NEVER horizontal page scroll from 320 px; NEVER hide information for lack of space (show it stacked).
- Every control has an accessible name in the screen language; focus always visible in the `ring` token; overlays trap focus, close on Esc and return focus.
- Targets >= 24 × 24 px; >= 40 px for icon buttons on coarse pointers.
- Hover is never the only path: hover content also opens on focus, stays while hovered or focused, closes on Esc (WCAG 1.4.13).
- Tables: real table element with caption; identification, status and actions always visible; hidden columns show their values stacked in the first cell. Charts: a table view with the same values.
- Motion only on data, respecting `prefers-reduced-motion` and a user toggle; no loops, bounces or fades. Exception: a game's UI may animate beyond data, loops included, still respecting both.
- UI texts come from translation dictionaries; NEVER sentences assembled from fragments.

## Verify

- Any layout change: check in a real browser at 320, 390, 768, 1024 and 1280 px, per the session's verification mode (`rules/quality.md` "Verification mode"); report what was not checked (screen readers, other browsers, forced colors).
