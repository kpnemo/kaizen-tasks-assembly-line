# Spec: #19 Change app accent color from blue to dark brown/reddish

Context: docs/superpowers/briefs/2026-09-10-issue-19-change-app-accent-color-from-blue-to-dar.md

## What

The app's accent moves from indigo (oklch hue 272) to oxblood, a dark reddish brown, in both themes, and the accent becomes a single variable. Today five tokens in `frontend/src/styles/globals.css` each carry their own indigo literal, twice (light and dark). After this change one variable, `--brand: oklch(0.42 0.13 30)`, is the accent, and the five tokens in both theme blocks derive from it with CSS relative color syntax (`oklch(from var(--brand) <lightness> calc(c * <factor>) h)`). A future refresh changes that one line; the two values that cannot read CSS (the browser theme-color meta and the favicon tile) are pinned to it by a test that computes the hex from `--brand` and fails until they match. Neutral grays, backgrounds and the destructive red do not change.

Decision from the design review (the product owner, 2026-09-10 18:30): approach B, "create a variable for styling and be able in the future in one place to change accent color", replaces the recommended token-by-token edit.

## Who

The product manager asked for a brand refresh. Every signed-in user sees it on every screen: buttons, links, the checked checkbox, the focus ring, the AI badges and chips, the progress bar, the brand mark, the text-selection highlight, the tab icon and the mobile address bar.

## Behavior

Nothing behavioural changes. One new variable in `:root`, and the five accent tokens in both blocks derive from it. Lightness stays a literal per token, because it is what keeps text readable on each ground; chroma scales from the brand's; hue is the brand's.

| Token | Light (`:root`) today | Light new | Dark (`.dark`) today | Dark new |
|---|---|---|---|---|
| `--brand` | (none) | `oklch(0.42 0.13 30)` | | inherited |
| `--primary` | `oklch(0.45 0.19 272)` | `var(--brand)` | `oklch(0.72 0.15 272)` | `oklch(from var(--brand) 0.72 calc(c * 0.85) h)` |
| `--primary-foreground` | `oklch(0.99 0 0)` | unchanged | `oklch(0.17 0.03 272)` | `oklch(from var(--brand) 0.17 calc(c * 0.25) h)` |
| `--accent` | `oklch(0.93 0.04 272)` | `oklch(from var(--brand) 0.93 calc(c * 0.25) h)` | `oklch(0.36 0.08 272)` | `oklch(from var(--brand) 0.36 calc(c * 0.45) h)` |
| `--accent-foreground` | `oklch(0.3 0.15 272)` | `oklch(from var(--brand) 0.32 calc(c * 0.8) h)` | `oklch(0.93 0.04 272)` | `oklch(from var(--brand) 0.93 calc(c * 0.25) h)` |
| `--ring` | `oklch(0.45 0.19 272)` | `var(--brand)` | `oklch(0.72 0.15 272)` | `oklch(from var(--brand) 0.72 calc(c * 0.85) h)` |

Resolved, the new values are the oxblood set from the round: light primary `oklch(0.42 0.13 30)`, dark primary `oklch(0.72 0.11 30)`, light wash `oklch(0.93 0.03 30)`, dark wash `oklch(0.36 0.06 30)`. The dark hue is 30 rather than the round's 32 so that one variable serves both themes; the difference is not visible.

Outside the tokens: `frontend/index.html` `<meta name="theme-color">` and the `<rect>` fill in `frontend/public/favicon.svg` change from `#4744b8` to `#86281d`, the sRGB form of `--brand`. Neither file can read a CSS variable, so the test derives the hex from `--brand` and asserts both files carry it; changing `--brand` later makes that test name the new hex. The identity comment at the top of `globals.css` says where the accent lives and names the two files that follow it by hand.

Relative color syntax (`oklch(from ...)`) is supported by every current browser and passes through Lightning CSS, the minifier behind Tailwind 4 and Vite, unchanged when its base is a `var()`; the build and the screenshots confirm it.

Decisions from the round (all recommendations taken): oxblood as the shade; the destructive red `oklch(0.55 0.2 27)` stays as it is; the favicon and theme-color move with the accent. Decisions taken from the issue text: the pale accent wash and the focus ring follow the accent ("all accent-coloured elements"); the dark theme gets the lighter oxblood so the accent still reads on a dark ground; the user-selectable "Indigo" tag colour in `src/lib/tag-palette.ts` is data, not the accent, and stays.

## Acceptance criteria as tests

Vitest runs with `css: false`, so no component test can observe a colour. The criteria are checked the way this repo checks source-level facts (`tests/product-map.test.ts` reads `router.tsx`): a new `frontend/tests/accent-tokens.test.ts` reads the files as text and asserts on them. Effective criteria, each with its test:

1. Primary button background is dark brown/reddish, not blue. Reworded in the round and the design review: `--brand` is declared once, in `:root`, as `oklch(0.42 0.13 30)`, and `--primary` is `var(--brand)` in light and derives from `--brand` in dark. — `tests/accent-tokens.test.ts` › "the brand accent is declared once, as oxblood" and "primary derives from the brand in both themes"; the default `Button` variant paints `bg-primary` — "the primary button, the checked checkbox and the focus ring use the tokens".
2. Active/focused controls (checkboxes, toggles) show the new colour. Reworded: `--ring`, `--accent` and `--accent-foreground` derive from `--brand` in both blocks (each value is `var(--brand)` or `oklch(from var(--brand) ...)`), the checkbox checked state uses `bg-primary`, and the global `:focus-visible` outline uses `var(--ring)`. — "every accent token in both themes derives from the brand" and "the primary button, the checked checkbox and the focus ring use the tokens".
3. Links display in the new accent colour. Reworded: no accent token in either block keeps a literal hue 272, no file under `src/` uses a `blue-*`, `indigo-*` or `sky-*` Tailwind class or the old `#4744b8`, and the `link` button variant and the page links use `text-primary`. — "nothing keeps the indigo hue or a hard-coded blue".
4. From the round: the theme-color meta and the favicon tile carry the brand as hex. — "the browser theme-color and the favicon carry the brand as hex": the test converts `--brand` to sRGB hex (`#86281d`) and asserts both files contain it.

There is no error state: the change has no data path, so the happy-path plus error-state rule of `add-frontend-feature` does not apply, and the pull request says so.

## Looks

Light theme: primary buttons are deep wine-brown with white text; links and the brand mark are the same wine-brown; the checked checkbox fills wine-brown with a white check; the focus ring is a 3px wine-brown outline; AI chips, the AI banner, the active nav item and menu hover sit on a pale warm blush with dark wine-brown text; the progress bar and "Suggested by AI" badge are wine-brown.

Dark theme: the accent lifts to a dusty rose-brown (`oklch(0.72 0.11 32)`) so it still reads on the dark ground; button text on it is near-black brown; the wash is a muted dark brown with pale rose text. Neutrals in both themes are untouched: warm off-white light background, cool near-black dark background, the same grays.

Screenshots: `tasks` (the shell, the brand, the primary create control, the empty state) and `theme-focused` (the focus ring) in both themes, captured by `scripts/screenshot.mjs`, committed under `docs/screenshots/` and embedded in the pull request.

## Out of scope

- Neutral grays and backgrounds (from the issue).
- The destructive red and error states (round, Q2).
- The tag colour palette, including its "Indigo" entry.
- Any layout, copy or behaviour change; any new primitive.
- Rewriting the 2026-09-08 plan and spec under `frontend/docs/superpowers/` that record the indigo choice; they are history.

## Repos and files

Only `kaizen-tasks-web` (`frontend/`), on `feat/19-change-app-accent-color-from-blue-to-dar`:

- `src/styles/globals.css`: the new `--brand` variable, the nine derived token values above, and the identity comment.
- `index.html`: the theme-color meta.
- `public/favicon.svg`: the tile fill.
- `tests/accent-tokens.test.ts`: new.
- `docs/screenshots/{tasks,theme-focused}-{light,dark}.png`: regenerated.
- `CHANGELOG.md` (`[Unreleased]`, Changed), `README.md` (feature list bullet), `docs/product-map.md` (regenerated by `npm run product-map`).

No architectural file changes, so no ADR. No API change.
