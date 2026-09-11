# Spec: #29 Simplify header into theme toggle and user dropdown menu

Context: docs/superpowers/briefs/2026-09-11-issue-29-simplify-header-into-theme-toggle-and-us.md

## What

Replace the header's three-item theme menu with a single icon-only button that cycles light → dark → system on each click, and move Feature Request, Pipeline, and Log out out of the header's top-level row into a dropdown menu opened from the username.

## Who

Any signed-in user, on every page (the header renders in the shared `AppShell` layout).

## Behavior

- The header's right-hand group becomes, left to right: the cycling theme button, then the account menu.
- The theme button is icon-only (sun / moon / monitor from `lucide-react`, matching `THEME_OPTIONS`'s existing order), carries an accessible name that states the current mode (e.g. "Theme: Light, switch to dark"), and calls the existing `useUpdateTheme` mutation with the next mode in the cycle on each click. No visual submenu.
- The account menu's trigger is a `Button` named by the user's display name (unchanged from today's visible name) that opens a `DropdownMenu` with, in order: "Request a feature" (navigates to `/request-feature`, shown only when `features.featureRequests` is on, same condition `FeatureRequestLink` uses today), "Pipeline" (navigates to `/pipeline`, shown only when `features.pipeline` is on, same condition `PipelineLink` uses today), a separator, then "Log out" (calls the existing `useLogout` mutation).
- Persistence of the chosen theme is unchanged: `useUpdateTheme` → `authStore` → `PATCH /auth/me` (ADR 0006); no new persistence mechanism.
- `FeatureRequestLink.tsx` and `PipelineLink.tsx` are removed; nothing else in the app renders them (confirmed by exploration).

## Acceptance criteria restated as tests

1. The icon shown always matches the current mode — `src/features/theme/ThemeToggle.test.tsx::"shows the icon for the current theme mode"`
2. Clicking the icon cycles light, dark, then system in order — `src/features/theme/ThemeToggle.test.tsx::"cycles light, dark, then system on each click"`
3. The chosen mode is remembered after reloading the page — `src/features/theme/ThemeToggle.test.tsx::"persists the chosen mode across reload"` (exercises the existing `useUpdateTheme`/`authStore` path, unchanged by this work)

Additional tests needed to cover the rest of the confirmed behavior (not separately numbered acceptance criteria in the issue, but required for the deliverable to work):

4. The account menu trigger is named by the display name and opens a menu — `src/features/auth/AccountMenu.test.tsx::"opens the account menu from the display name button"`
5. The menu contains "Request a feature" and "Pipeline" only when their feature flags are on, and always contains "Log out" — `AccountMenu.test.tsx::"shows Request a feature and Pipeline only when their flags are on"`, `::"always shows Log out"`
6. Choosing "Log out" from the menu logs the user out — `AccountMenu.test.tsx::"logs out from the menu"`; and the cross-repo smoke test's existing fallback path (`button` named by the display name → `menuitem "Log out"`) passes unchanged against this shape.
7. `src/app/router.test.tsx` and `src/features/auth/auth.test.tsx` are updated to open the account menu before asserting "Log out", since it is no longer a bare header button.

## Out of scope

- Behavior of existing pages other than the header (per the issue).
- Any change to theme persistence, auth, or the API contract — this is a web-only, UI-only change.
- A keyboard shortcut or animation for the cycling button.

## Looks

- Theme button: icon-only, no visible label, `size="icon"` variant matching the header's other `Button`s; icon changes with mode (`Sun`, `Moon`, `Monitor` from `lucide-react`, `size-4`, `aria-hidden="true"` since the button's own `aria-label` names the control per `ui-conventions.md`).
- Account menu trigger: same `Button` styling the header uses today for its right-hand group (`variant="outline"`), showing the display name and a small chevron, visible at all viewport widths this header supports (no `hidden below xl`, since it is now the only way to reach Feature Request, Pipeline, and Log out).
- Menu: `DropdownMenu`/`DropdownMenuContent` aligned to the trigger's end, items in order Request a feature, Pipeline, a `DropdownMenuSeparator`, Log out; each item carries a lucide icon per `ui-conventions.md`'s composition table.
- Both themes: uses the existing `dropdown-menu` and `button` primitives' theme tokens; no new colors introduced.
- Checked at 125% zoom per `ui-conventions.md`; 44px hit areas preserved (unchanged `Button` sizing).

## Repos and files touched

`kaizen-tasks-web` only:

- `src/app/layout.tsx` — header composition
- `src/features/theme/ThemeToggle.tsx`, `src/features/theme/hooks.ts` (if a cycle helper is needed), `src/features/theme/ThemeToggle.test.tsx`
- `src/features/auth/AccountMenu.tsx` (new), `src/features/auth/AccountMenu.test.tsx` (new)
- `src/features/feature-request/FeatureRequestLink.tsx`, `src/features/pipeline/PipelineLink.tsx` — removed
- `src/app/router.test.tsx`, `src/features/auth/auth.test.tsx` — updated Log out queries
- `README.md` — selector-contract table description of the header
- `CHANGELOG.md` — `[Unreleased]` bullet
- `docs/screenshots/header-{light,dark}.png` — new, per the screenshot step
