# Briefing: #29 Simplify header into theme toggle and user dropdown menu

- Summary: The signed-in header is cluttered — a theme menu, a Feature Request link, a Pipeline link, and a Log out button all sit as separate controls. Replace the theme control with a single icon-only button that cycles light → dark → system on each click, and move Feature Request, Pipeline, and Log out into a dropdown menu opened from the username.
- Triage: readiness 16, clarity 4, complexity 2, risk 2
- UI: visible
- Repos: kaizen-tasks-web

## What exists today

`src/app/layout.tsx` renders the whole signed-in header in one place: wordmark → nav (`Tasks`, `Tags`, `FeatureRequestLink`, `PipelineLink`) → a right-hand group of `ThemeToggle`, the display name as a plain non-interactive `<span>` (hidden below the `xl` breakpoint), and a `Button` "Log out" (`variant="outline"`, icon + text) calling `useLogout()` from `src/features/auth/hooks.ts`.

`ThemeToggle` (`src/features/theme/ThemeToggle.tsx` + `hooks.ts` + `theme.ts`) is already a `DropdownMenu`, not a toggle: a trigger button named "Theme" opens a `DropdownMenuRadioGroup` with three `menuitemradio` items in the order light, dark, system (`THEME_OPTIONS`). Persistence is already solved and does not need to change: `useUpdateTheme` writes optimistically to `authStore` then `PATCH /auth/me` (ADR 0006 — the session user is the source of truth), with `localStorage` (`kaizen.theme`) only as a pre-hydration cache. `useApplyTheme` sets the `dark` class and `color-scheme`, and only listens to OS changes while the preference is `system`. So "remembered after reload" is already handled; the new work is turning the three-item menu into a click-to-cycle icon button in the same order the `THEME_OPTIONS` array already uses.

`FeatureRequestLink` and `PipelineLink` are `NavButton`-style links (icon + visible text, rendered conditionally on API feature flags). `useLogout` posts `/auth/logout`, clears the auth store and query cache, and navigates to `/login`. `src/components/ui/dropdown-menu.tsx` is an existing shadcn/Radix primitive already used three places (`ThemeToggle`, `AddTagPopover`, `StepRow`), so a second dropdown for the account menu is an established pattern, not new infrastructure. No component in the header is duplicated elsewhere.

**The cross-repo smoke test already anticipates this exact shape.** `webapp/smoke/tests/smoke.spec.ts` (log-out step) and `webapp/smoke/README.md` already document two accepted shapes for "log out": a direct `button "Log out"`, **or** a `button` named after the display name that opens a menu with a `menuitem "Log out"` inside. So moving Log out into a username-triggered dropdown does not break the cross-repo contract — it is the shape the smoke test was already written to expect. This means the dropdown's trigger must be a `button` whose accessible name is the user's display name (not an icon-only avatar), and Log out inside it must keep the accessible name "Log out" (role `menuitem` is fine).

This repo's own tests will need updating regardless: `src/features/auth/auth.test.tsx` and `src/app/router.test.tsx` query `getByRole("button", { name: "Log out" })` today and will need to open the account menu first once Log out moves inside it; `ThemeToggle.test.tsx` asserts the current three-item radio-menu shape and needs rewriting for the cycling button. `frontend/README.md`'s own selector-contract table (not the smoke test itself) should be updated to describe the new shapes.

## Touched areas

- `src/app/layout.tsx` — the header: remove the standalone `ThemeToggle`, `FeatureRequestLink`, `PipelineLink`, and "Log out" button from the top-level row; add the icon-only theme cycle button and a username-triggered dropdown menu containing Feature Request, Pipeline, and Log out.
- `src/features/theme/ThemeToggle.tsx`, `src/features/theme/hooks.ts` — replace the radio-menu with a cycling icon button (reuses `THEME_OPTIONS`, `useUpdateTheme`, `useApplyTheme` as-is).
- `src/features/theme/ThemeToggle.test.tsx` — rewritten for the cycling button.
- `src/features/auth/auth.test.tsx`, `src/app/router.test.tsx` — updated to open the account menu before asserting "Log out".
- `frontend/README.md` — selector-contract table updated to describe the new header shape.

## Mockups seen

None — the issue's "Looks or mockup" section was not filled in; the interview transcript in the body describes the intended look in words only.

## Unknowns

None — the single exploration pass answered all four questions within its time and turned up the smoke test's existing two-shape contract, which resolves what looked like it might be a blocker.

## Open questions

None. The rubric's own clarity questions do not apply (clarity is 4, not below 3), and the exploration settled the one real risk (the Log out role/location change against the cross-repo contract). The remaining decision — the exact composition of the icon-only toggle and the account dropdown — is a design choice, not an open question, and is handled by the design question in Step 5.
