# Briefing: #19 Change app accent color from blue to dark brown/reddish

- Summary: The product manager wants a brand refresh. Every accent-coloured element (buttons, links, active and focused controls) moves from today's blue to a dark brown/reddish tone, app-wide. Neutral grays and backgrounds stay as they are.
- Triage: readiness 17, clarity 4, complexity 2, risk 1
- UI: visible
- Repos: kaizen-tasks-web

## What exists today

The accent is indigo, oklch hue 272 (`oklch(0.45 0.19 272)` in light, `oklch(0.72 0.15 272)` in dark), declared once in `frontend/src/styles/globals.css` as the tokens `--primary`, `--primary-foreground`, `--accent`, `--accent-foreground` and `--ring`, in a `:root` block and a `.dark` block. The `@theme inline` block maps them to Tailwind utilities (`bg-primary`, `text-primary`, `bg-accent`, `ring-ring`), so every component follows the tokens; no component hard-codes a blue or indigo class. A comment in that file names the identity ("one accent (indigo, the Japanese dye 'ai')").

What the indigo carries today: primary buttons, links (`text-primary underline` on the auth pages, task detail, not-found page), the logo mark and brand link in the header, the checkbox checked state, the progress bar, the "Suggested by AI" badge, the pale accent wash on AI chips, the AI banner, the active nav item and menu hover, the text-selection highlight, and every focus ring (`:focus-visible { outline: 3px solid var(--ring) }`).

Two indigo values sit outside the tokens: `frontend/index.html` line 29, `<meta name="theme-color" content="#4744b8">`, and `frontend/public/favicon.svg`, a white mark on an indigo tile (`fill="#4744b8"`).

The theme control is a native select, not toggle buttons; there is no switch primitive. "Toggles" in the request therefore maps to the checkbox checked state, the active nav item, and the focus ring on any control.

The tag palette (`src/lib/tag-palette.ts`) includes a user-selectable "Indigo" tag colour. That is user data, not the app accent, and stays.

## Touched areas

- `frontend/src/styles/globals.css`: the five accent tokens in `:root` and `.dark`, and the identity comment.
- `frontend/index.html`: the `theme-color` meta.
- `frontend/public/favicon.svg`: the tile fill.
- `frontend/tests/` or `frontend/src/styles/`: a new token test reading `globals.css` as text (vitest runs with `css: false`, so computed styles are not available; the repo's pattern is `readFileSync` plus assertions, as in `tests/product-map.test.ts`).
- `frontend/docs/screenshots/`: `tasks-{light,dark}.png` and `theme-focused-{light,dark}.png` change; `theme-focused` exists to show the focus ring.
- `frontend/CHANGELOG.md`, `frontend/README.md` feature list, `frontend/docs/product-map.md` (regenerated).
- Verify only, no edits: the token consumers in `src/components/ui/{button,badge,checkbox,input,textarea,dropdown-menu}.tsx`, `src/app/layout.tsx`, the auth pages, the task and feature-request components.

## Mockups seen

none

## Unknowns

none

## Open questions

1. blocker: Which dark brown/reddish tone, exactly? "Dark brown/reddish" names no value, so no test can check it as written — suggested answer: oxblood, `oklch(0.42 0.13 30)` in light and `oklch(0.72 0.11 32)` in dark, with the accent wash and ring derived from the same hue; the testable criterion becomes "the `--primary` and `--ring` tokens equal those values in their blocks and no token keeps hue 272".
2. The destructive red (`oklch(0.55 0.2 27)`, delete buttons and error states) sits in the same hue family as a reddish accent. Keep it as it is? — suggested answer: yes, leave destructive untouched; the accent is darker and less saturated, so delete still reads as its own colour.
3. The favicon tile and the browser theme-color are indigo but sit outside the app's UI. Move them with the accent? — suggested answer: yes, "app-wide" includes what the browser shows for the app; both take the new light-theme primary.

Decisions taken without asking (settled by the issue text or the conventions): the pale accent wash (AI chips, banner, active nav, menu hover) and the focus ring move with the accent, because the request says all accent-coloured elements; the dark theme gets a lighter version of the same hue, because `docs/ui-conventions.md` requires both themes; the "Indigo" entry in the tag palette stays, because it is user data, not the accent; the 2026-09-08 plan and spec under `frontend/docs/superpowers/` that describe the indigo identity are historical records and are not rewritten.
