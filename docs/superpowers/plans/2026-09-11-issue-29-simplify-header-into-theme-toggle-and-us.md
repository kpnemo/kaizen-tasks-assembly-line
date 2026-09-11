# Simplify header into theme toggle and user dropdown menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the header's three-item theme menu with a single icon-only button that cycles light → dark → system, and move Feature Request, Pipeline, and Log out into a dropdown menu opened from the username.

**Architecture:** `ThemeToggle` is rewritten in place from a `DropdownMenu` to a plain cycling `Button` (same hooks, same persistence). A new `AccountMenu` component owns a fresh `DropdownMenu` triggered by the display name, with its own `DropdownMenuItem`s for Feature Request, Pipeline, and Log out; `FeatureRequestLink` and `PipelineLink` are retired since `layout.tsx` was their only caller.

**Tech Stack:** React 19, TypeScript strict, Tailwind 4, shadcn/ui (`dropdown-menu`, `button`), TanStack Query, react-router 7, Vitest + Testing Library + MSW.

**Spec:** docs/superpowers/specs/2026-09-11-issue-29-simplify-header-into-theme-toggle-and-us.md

## Global Constraints

- Every request goes through the existing typed client; this change adds no API calls (`useUpdateTheme`, `useLogout`, `useFeatureRequestAvailable`, `usePipelineAvailable` are all unchanged, existing hooks).
- The cross-repo smoke test contract for "log out" (`webapp/smoke/README.md`, `webapp/smoke/tests/smoke.spec.ts`) already accepts a `button` named by the display name opening a menu with a `menuitem "Log out"` — this plan produces exactly that shape, unchanged.
- Projector rules: 18px base text, 44px hit areas, visible focus ring, no hover-only control (`docs/ui-conventions.md`).
- Every icon inside a `Button`/`DropdownMenuItem` carries `aria-hidden="true"`; the control's own accessible name (an `aria-label` or its visible text) is what announces it.
- `npm run docs:check` must never be run directly (Stop-hook mode expects hook JSON on stdin); the gate to run here is `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci`, once, at the end of Task 3.

---

### Task 1: Rewrite ThemeToggle as a cycling icon-only button

Follows `frontend/.claude/skills/add-frontend-feature/SKILL.md`.

**Files:**

- Modify: `frontend/src/features/theme/ThemeToggle.tsx`
- Modify: `frontend/src/features/theme/ThemeToggle.test.tsx`

**Interfaces:**

- Consumes (unchanged, from `./hooks` and `./theme`): `useThemePreference(): ThemePreference`, `useUpdateTheme(): UseMutationResult<{ theme: ThemePreference }, unknown, ThemePreference, ThemePreference>`, `THEME_OPTIONS: { value: ThemePreference; label: string }[]` (order: light, dark, system).
- Produces: `ThemeToggle()`, same export name and path (`@/features/theme/ThemeToggle`) that `layout.tsx` already imports — Task 2 does not need to change that import. Its accessible name is now `"Theme: <Current>, switch to <Next>"` instead of the old fixed `"Theme"`.

- [ ] **Step 1: Write the failing test**

Replace the whole file `frontend/src/features/theme/ThemeToggle.test.tsx` with:

```tsx
import { screen, waitFor } from "@testing-library/react";
import { http } from "msw";
import { afterEach, describe, expect, it } from "vitest";
import type { ThemePreference } from "@/api/models";
import { demoUser } from "../../../tests/msw/fixtures";
import { API, err, ok } from "../../../tests/msw/handlers";
import { server } from "../../../tests/msw/server";
import { renderApp } from "../../../tests/render";
import { THEME_STORAGE_KEY } from "./theme";

const original = window.matchMedia;

/** Pretends the operating system asks for dark (or light), the way a real browser would. */
function osPrefersDark(matches: boolean) {
  window.matchMedia = ((query: string) =>
    ({
      matches: query.includes("prefers-color-scheme: dark") ? matches : false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList) as typeof window.matchMedia;
}

afterEach(() => {
  window.matchMedia = original;
  document.documentElement.classList.remove("dark");
  document.documentElement.style.colorScheme = "";
  localStorage.clear();
});

/** The header's icon-only theme control: its accessible name states the current mode and what one
 *  more click switches to. */
const toggle = () => screen.getByRole("button", { name: /^Theme:/ });

/** Signs in with the given stored preference, the way a fresh device would. */
async function signInWith(theme: ThemePreference) {
  server.use(http.get(`${API}/auth/me`, () => ok({ user: { ...demoUser, theme } })));
  const rendered = renderApp({ route: "/tasks", session: "restoring" });
  await screen.findByRole("button", { name: /^Theme:/ });
  return rendered;
}

/** Gates `PATCH /auth/me` so a test can assert state while the save is genuinely mid-flight. */
function gatedSave(theme: ThemePreference) {
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    release = () => resolve();
  });
  server.use(
    http.patch(`${API}/auth/me`, async () => {
      await gate;
      return ok({ user: { ...demoUser, theme } });
    }),
  );
  return () => release();
}

describe("theme toggle", () => {
  it("shows the icon and names the current mode on the control", async () => {
    await signInWith("dark");
    expect(document.documentElement).toHaveClass("dark");
    expect(toggle()).toHaveAccessibleName("Theme: Dark, switch to System");
    expect(toggle().querySelector("svg")).toHaveClass("lucide-moon");
  });

  it("cycles light, dark, then system on each click", async () => {
    const { user } = await signInWith("light");
    expect(toggle()).toHaveAccessibleName("Theme: Light, switch to Dark");
    await user.click(toggle());
    await waitFor(() => expect(toggle()).toHaveAccessibleName("Theme: Dark, switch to System"));
    await user.click(toggle());
    await waitFor(() => expect(toggle()).toHaveAccessibleName("Theme: System, switch to Light"));
    await user.click(toggle());
    await waitFor(() => expect(toggle()).toHaveAccessibleName("Theme: Light, switch to Dark"));
  });

  it("applies the next theme to the document immediately on click", async () => {
    const { user } = await signInWith("light");
    await user.click(toggle());
    // No waitFor: the theme must be on the document before the save round trip finishes.
    expect(document.documentElement).toHaveClass("dark");
    expect(document.documentElement.style.colorScheme).toBe("dark");
  });

  it("cycling from dark to system follows prefers-color-scheme", async () => {
    osPrefersDark(true);
    const { user } = await signInWith("dark");
    await user.click(toggle());
    expect(document.documentElement).toHaveClass("dark");
    expect(document.documentElement.style.colorScheme).toBe("dark");
  });

  it("cycling from system to light removes the dark class", async () => {
    const { user } = await signInWith("system");
    await user.click(toggle());
    expect(document.documentElement).not.toHaveClass("dark");
    expect(document.documentElement.style.colorScheme).toBe("light");
  });

  it("persists the chosen mode across reload", async () => {
    const saved: unknown[] = [];
    const { user } = await signInWith("system");
    server.use(
      http.patch(`${API}/auth/me`, async ({ request }) => {
        const body = await request.json();
        saved.push(body);
        return ok({ user: { ...demoUser, theme: "light" } });
      }),
    );
    await user.click(toggle());
    await waitFor(() => expect(saved).toEqual([{ theme: "light" }]));
    expect(toggle()).toHaveAccessibleName("Theme: Light, switch to Dark");
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("light");
  });

  it("shows the API error when saving fails and puts the choice back", async () => {
    const { user } = await signInWith("light");
    server.use(http.patch(`${API}/auth/me`, () => err("INTERNAL", "Could not save your theme")));
    await user.click(toggle());
    expect(await screen.findByText("Could not save your theme")).toBeInTheDocument();
    await waitFor(() => expect(document.documentElement).not.toHaveClass("dark"));
    expect(toggle()).toHaveAccessibleName("Theme: Light, switch to Dark");
  });

  it("disables the control while a save is in flight, and re-enables it once it settles", async () => {
    const { user } = await signInWith("light");
    const release = gatedSave("dark");
    await user.click(toggle());
    // Optimistic apply still happens at once; only the save itself is gated.
    expect(document.documentElement).toHaveClass("dark");
    expect(toggle()).toBeDisabled();
    expect(toggle()).toHaveAccessibleName("Theme: Dark, switch to System");
    release();
    await waitFor(() => expect(toggle()).not.toBeDisabled());
  });

  it("the session user's saved theme overrides a different value cached on this device", async () => {
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    await signInWith("dark");
    expect(document.documentElement).toHaveClass("dark");
    expect(toggle()).toHaveAccessibleName("Theme: Dark, switch to System");
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("dark");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvm use && npm test -- ThemeToggle` (from `frontend/`)
Expected: FAIL — no `button` with an accessible name matching `/^Theme:/` exists yet (the current control's fixed name is `"Theme"` and it opens a menu instead of cycling).

- [ ] **Step 3: Write the minimal implementation**

Replace the whole file `frontend/src/features/theme/ThemeToggle.tsx` with:

```tsx
import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";
import type { ThemePreference } from "@/api/models";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { useThemePreference, useUpdateTheme } from "./hooks";
import { THEME_OPTIONS } from "./theme";

const ICONS: Record<ThemePreference, LucideIcon> = { light: Sun, dark: Moon, system: Monitor };

/** Cycles light, dark, then system on each click, in `THEME_OPTIONS`'s order, and saves the
 *  choice to the account (ADR 0006). Icon-only: the accessible name states the current mode and
 *  what one more click switches to, so the state is available without a visible word. */
export function ThemeToggle() {
  const preference = useThemePreference();
  const update = useUpdateTheme();
  const currentIndex = Math.max(
    0,
    THEME_OPTIONS.findIndex((option) => option.value === preference),
  );
  const current = THEME_OPTIONS[currentIndex];
  const next = THEME_OPTIONS[(currentIndex + 1) % THEME_OPTIONS.length];
  const CurrentIcon = ICONS[current.value];
  return (
    <Button
      variant="outline"
      size="icon"
      aria-label={`Theme: ${current.label}, switch to ${next.label}`}
      disabled={update.isPending}
      onClick={() => update.mutate(next.value)}
    >
      {update.isPending ? <Spinner aria-hidden="true" /> : <CurrentIcon aria-hidden="true" />}
    </Button>
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npm test -- ThemeToggle`
Expected: PASS, all 9 tests.

- [ ] **Step 5: Repo checks**

Run, in order: `npm run typecheck`, `npm run lint`. Both must exit 0. (`layout.tsx` still imports the old `DropdownMenu`-based `ThemeToggle` API only by name — Task 2 does not touch `ThemeToggle`'s import line, so no other file breaks here.)

- [ ] **Step 6: Commit**

```bash
cd frontend
git add src/features/theme/ThemeToggle.tsx src/features/theme/ThemeToggle.test.tsx
git commit -m "feat: cycle the theme toggle instead of opening a menu (#29)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Add the account menu and retire the header's standalone links

Follows `frontend/.claude/skills/add-frontend-feature/SKILL.md`.

**Files:**

- Create: `frontend/src/features/auth/AccountMenu.tsx`
- Create: `frontend/src/features/auth/AccountMenu.test.tsx`
- Modify: `frontend/src/app/layout.tsx`
- Modify: `frontend/src/app/router.test.tsx`
- Modify: `frontend/src/features/auth/auth.test.tsx`
- Modify: `frontend/src/components/nav-button.tsx` (doc comment only)
- Delete: `frontend/src/features/feature-request/FeatureRequestLink.tsx`
- Delete: `frontend/src/features/pipeline/PipelineLink.tsx`

**Interfaces:**

- Consumes (all unchanged, existing exports): `useFeatureRequestAvailable(): { available: boolean | undefined }` from `@/features/feature-request/hooks`; `usePipelineAvailable(): { available: boolean | undefined }` from `@/features/pipeline/hooks`; `useLogout(): UseMutationResult<void, unknown, void>` from `@/features/auth/hooks`; `useSession(): { user: User | null }` from `@/features/auth/useSession`.
- Produces: `AccountMenu({ displayName }: { displayName: string })`, exported from `@/features/auth/AccountMenu`, rendered by `layout.tsx`'s `AppShell`.

- [ ] **Step 1: Write the failing test**

Create `frontend/src/features/auth/AccountMenu.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import { http } from "msw";
import { describe, expect, it } from "vitest";
import { authStore } from "@/api/auth-store";
import { API, healthBody, ok } from "../../../tests/msw/handlers";
import { server } from "../../../tests/msw/server";
import { renderApp } from "../../../tests/render";

/** The header's account menu: the display name button opens it. */
const trigger = () => screen.getByRole("button", { name: "Demo" });

describe("account menu", () => {
  it("opens from the display name and lists Request a feature, Pipeline, and Log out", async () => {
    const { user } = renderApp({ route: "/tasks" });
    await screen.findByRole("heading", { name: "Tasks" });
    await user.click(trigger());
    expect(
      await screen.findByRole("menuitem", { name: "Request a feature" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "Pipeline" })).toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "Log out" })).toBeInTheDocument();
  });

  it("hides Request a feature and Pipeline when their flags are off, and always shows Log out", async () => {
    server.use(http.get(`${API}/health`, () => ok(healthBody(false))));
    const { user } = renderApp({ route: "/tasks" });
    await screen.findByRole("heading", { name: "Tasks" });
    await user.click(trigger());
    expect(await screen.findByRole("menuitem", { name: "Log out" })).toBeInTheDocument();
    expect(screen.queryByRole("menuitem", { name: "Request a feature" })).not.toBeInTheDocument();
    expect(screen.queryByRole("menuitem", { name: "Pipeline" })).not.toBeInTheDocument();
  });

  it("navigates to Request a feature from the menu", async () => {
    const { user } = renderApp({ route: "/tasks" });
    await screen.findByRole("heading", { name: "Tasks" });
    await user.click(trigger());
    await user.click(await screen.findByRole("menuitem", { name: "Request a feature" }));
    expect(await screen.findByRole("heading", { name: "Request a feature" })).toBeInTheDocument();
  });

  it("logs out from the menu", async () => {
    let logouts = 0;
    server.use(
      http.post(`${API}/auth/logout`, () => {
        logouts += 1;
        return new Response(null, { status: 204 });
      }),
    );
    const { user } = renderApp({ route: "/tasks" });
    await screen.findByRole("heading", { name: "Tasks" });
    await user.click(trigger());
    await user.click(await screen.findByRole("menuitem", { name: "Log out" }));
    expect(await screen.findByRole("heading", { name: "Log in" })).toBeInTheDocument();
    await waitFor(() => expect(logouts).toBe(1));
    expect(authStore.getState()).toEqual({ status: "anonymous", token: null, user: null });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm test -- AccountMenu`
Expected: FAIL — `frontend/src/features/auth/AccountMenu.tsx` does not exist yet, and no button named "Demo" is in the header (the display name is a plain, non-interactive `<span>` today).

- [ ] **Step 3: Write the minimal implementation**

Create `frontend/src/features/auth/AccountMenu.tsx`:

```tsx
import { ChevronDown, LogOut, Sparkles, Workflow } from "lucide-react";
import { NavLink } from "react-router";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useFeatureRequestAvailable } from "@/features/feature-request/hooks";
import { usePipelineAvailable } from "@/features/pipeline/hooks";
import { useLogout } from "./hooks";

/** The account menu: the display name opens Feature Request, Pipeline (each only when the API
 *  mounted its routes) and Log out. The trigger's accessible name is the display name alone (the
 *  chevron is `aria-hidden`); Log out keeps the accessible name "Log out" the smoke test relies on
 *  (`README.md`, "Selector contract") — now a menu item rather than a header button. */
export function AccountMenu({ displayName }: { displayName: string }) {
  const { available: featureRequestAvailable } = useFeatureRequestAvailable();
  const { available: pipelineAvailable } = usePipelineAvailable();
  const logout = useLogout();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" disabled={logout.isPending}>
          <span className="max-w-[12ch] truncate">{displayName}</span>
          <ChevronDown aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {featureRequestAvailable && (
          <DropdownMenuItem asChild>
            <NavLink to="/request-feature">
              <Sparkles aria-hidden="true" />
              Request a feature
            </NavLink>
          </DropdownMenuItem>
        )}
        {pipelineAvailable && (
          <DropdownMenuItem asChild>
            <NavLink to="/pipeline">
              <Workflow aria-hidden="true" />
              Pipeline
            </NavLink>
          </DropdownMenuItem>
        )}
        {(featureRequestAvailable || pipelineAvailable) && <DropdownMenuSeparator />}
        <DropdownMenuItem onSelect={() => logout.mutate()} disabled={logout.isPending}>
          <LogOut aria-hidden="true" />
          Log out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

Replace the whole file `frontend/src/app/layout.tsx` with:

```tsx
import { ListTodo, Tag } from "lucide-react";
import type { ReactNode } from "react";
import { NavLink, Outlet } from "react-router";
import { KaizenMark } from "@/components/kaizen-mark";
import { NavButton } from "@/components/nav-button";
import { WorkshopFooter } from "@/components/workshop-footer";
import { AccountMenu } from "@/features/auth/AccountMenu";
import { useSession } from "@/features/auth/useSession";
import { ThemeToggle } from "@/features/theme/ThemeToggle";

/** The signed-in frame: brand, primary nav, the theme control, and the account menu (Feature
 *  Request, Pipeline, and Log out, behind the display name). Renders the matched route in `main`,
 *  or `children` when a route mounts the shell itself (the catch-all, ADR 0009). */
export function AppShell({ children }: { children?: ReactNode }) {
  const { user } = useSession();
  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 border-b bg-card">
        <div className="mx-auto flex h-16 w-full max-w-5xl items-center gap-4 px-6">
          <NavLink to="/tasks" className="flex items-center gap-2 text-primary" data-nav>
            <KaizenMark />
            <span className="font-display text-2xl font-bold whitespace-nowrap">Kaizen Tasks</span>
          </NavLink>
          <nav aria-label="Primary" className="flex items-center gap-1">
            <NavButton to="/tasks" icon={ListTodo}>
              Tasks
            </NavButton>
            <NavButton to="/tags" icon={Tag}>
              Tags
            </NavButton>
          </nav>
          <div className="ml-auto flex items-center gap-3">
            <ThemeToggle />
            <AccountMenu displayName={user?.displayName ?? ""} />
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-6 py-8">{children ?? <Outlet />}</main>
      <WorkshopFooter />
    </div>
  );
}
```

Delete the two now-unused files:

```bash
git rm frontend/src/features/feature-request/FeatureRequestLink.tsx
git rm frontend/src/features/pipeline/PipelineLink.tsx
```

In `frontend/src/components/nav-button.tsx`, update the doc comment (its only change) since `FeatureRequestLink` no longer exists:

```diff
- *  active state is a shape and a weight rather than a tint, and every link carries an icon.
- *  react-router sets `aria-current="page"` on the active link; `data-nav` keeps the 44px hit area
- *  from globals.css. Used by the header and by FeatureRequestLink, so the two never drift. */
+ *  active state is a shape and a weight rather than a tint, and every link carries an icon.
+ *  react-router sets `aria-current="page"` on the active link; `data-nav` keeps the 44px hit area
+ *  from globals.css. Used by the header's primary nav (Tasks, Tags). */
```

In `frontend/src/app/router.test.tsx`, apply this diff:

```diff
     expect(tasks.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
     expect(tags.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
     expect(screen.queryByRole("link", { name: "Request a feature" })).not.toBeInTheDocument();
-    await user.click(screen.getByRole("button", { name: "Log out" }));
+    await user.click(screen.getByRole("button", { name: "Demo" }));
+    await user.click(await screen.findByRole("menuitem", { name: "Log out" }));
     expect(await screen.findByRole("heading", { name: "Log in" })).toBeInTheDocument();
   });

   it("renders a not-found page inside the shell for a signed-in user", async () => {
     renderApp({ route: "/nowhere" });
     expect(await screen.findByRole("heading", { name: "Page not found" })).toBeInTheDocument();
-    expect(screen.getByRole("button", { name: "Log out" })).toBeInTheDocument();
+    expect(screen.getByRole("button", { name: "Demo" })).toBeInTheDocument();
     expect(screen.getByRole("link", { name: "Go to your tasks" })).toHaveAttribute(
       "href",
       "/tasks",
     );
     expect(screen.getAllByRole("main")).toHaveLength(1);
   });

   it("renders the not-found page without the shell for an anonymous visitor", async () => {
     renderApp({ route: "/nowhere", session: "anonymous" });
     expect(await screen.findByRole("heading", { name: "Page not found" })).toBeInTheDocument();
-    expect(screen.queryByRole("button", { name: "Log out" })).toBeNull();
+    expect(screen.queryByRole("button", { name: "Demo" })).toBeNull();
     expect(screen.getByRole("link", { name: "Go to your tasks" })).toHaveAttribute(
       "href",
       "/tasks",
     );
```

In `frontend/src/features/auth/auth.test.tsx`, apply this diff:

```diff
     const { user, queryClient } = renderApp({ route: "/tags" });
-    await user.click(await screen.findByRole("button", { name: "Log out" }));
+    await user.click(await screen.findByRole("button", { name: "Demo" }));
+    await user.click(await screen.findByRole("menuitem", { name: "Log out" }));
     expect(await screen.findByRole("heading", { name: "Log in" })).toBeInTheDocument();
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test`
Expected: PASS, the whole suite (`AccountMenu.test.tsx`, `ThemeToggle.test.tsx`, `router.test.tsx`, `auth.test.tsx` included).

- [ ] **Step 5: Repo checks**

Run, in order: `npm run typecheck`, `npm run lint`. Both must exit 0 (confirms the two deleted files have no remaining importers and `layout.tsx`'s new imports resolve).

- [ ] **Step 6: Commit**

```bash
cd frontend
git add -A
git commit -m "feat: move Feature Request, Pipeline, and Log out into an account menu (#29)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Screenshot helpers, docs, and the final gate

Follows `frontend/.claude/skills/add-frontend-feature/SKILL.md`, "Screenshots" section.

The rename from a "Theme" menu button and a bare "Log out" button touches two Playwright screenshot helpers and one scenario outside the Vitest suite; fix those first so the screenshot step in this task actually runs, then do the docs.

**Files:**

- Modify: `frontend/scripts/screenshots/shared/facilitator.mjs`
- Modify: `frontend/scripts/screenshots/lib/signed-out.mjs`
- Delete: `frontend/scripts/screenshots/theme-open.mjs`
- Create: `frontend/scripts/screenshots/account-menu.mjs`
- Modify: `frontend/docs/ui-conventions.md` (one line)
- Modify: `frontend/README.md` (selector-contract table)
- Modify: `frontend/CHANGELOG.md`
- Modify: `frontend/docs/product-map.md` (regenerated, not hand-edited)
- Create: `frontend/docs/screenshots/account-menu-light.png`, `frontend/docs/screenshots/account-menu-dark.png`
- Delete: `frontend/docs/screenshots/theme-open-light.png`, `frontend/docs/screenshots/theme-open-dark.png` (if present; `git rm` no-ops harmlessly if they were never committed)

**Interfaces:** none — this task changes tooling and docs only, no exported runtime interface.

- [ ] **Step 1: Fix the facilitator screenshot helper**

In `frontend/scripts/screenshots/shared/facilitator.mjs`, apply this diff (the throwaway screenshot account is always named "Screenshot", set in `scripts/screenshot.mjs`):

```diff
   const signedIn = await page.evaluate(headerNames, FACILITATOR.displayName).catch(() => false);
   if (!signedIn) {
-    await page.getByRole("button", { name: "Log out" }).click();
+    await page.getByRole("button", { name: "Screenshot" }).click();
+    await page.getByRole("menuitem", { name: "Log out" }).click();
     await page.waitForURL(`${origin}/login`, { timeout: 15_000 });
     await page.getByLabel("Email").fill(FACILITATOR.email);
     await page.getByLabel("Password").fill(FACILITATOR.password);
     await page.getByRole("button", { name: "Log in" }).click();
     // Login returns to where the log-out happened (/pipeline), so the proof of the session is the
     // account's name in the header, not a URL.
     await page.waitForFunction(headerNames, FACILITATOR.displayName, { timeout: 15_000 });
   }

   // The account preference wins over the device (ADR 0006), and the runner drives the theme by
   // emulating prefers-color-scheme for the account it registered. Keeping the facilitator on
   // "System" hands that emulation the decision, in this pass and in the next one.
-  await page.getByRole("button", { name: "Theme" }).click();
-  await page.getByRole("menuitemradio", { name: "System" }).click();
+  for (let clicks = 0; clicks < 3; clicks += 1) {
+    const label = await page.getByRole("button", { name: /^Theme:/ }).getAttribute("aria-label");
+    if (label?.startsWith("Theme: System")) break;
+    await page.getByRole("button", { name: /^Theme:/ }).click();
+  }
   await page.waitForFunction(
     (want) => document.documentElement.classList.contains("dark") === want,
     dark,
     { timeout: 10_000 },
   );
```

- [ ] **Step 2: Fix the signed-out screenshot helper**

Replace the whole file `frontend/scripts/screenshots/lib/signed-out.mjs` with:

```js
// Shared by the signed-out scenarios (login, register). Not a scenario itself: it exports no route.
//
// The runner registers a user and logs in before any capture, and PublicOnly sends a signed-in
// visitor away from /login and /register to /tasks. A signed-out scenario therefore logs out inside
// ready(), before the runner compares the route, and then returns to its own route. The anonymous
// page shows the device's cached theme, not an account's, so the cache is set to "system" first:
// the runner emulates the OS colour scheme for each capture, and "system" follows it, which is how
// the dark capture of a signed-out screen can exist at all.
export async function signOut(page, route) {
  const accountMenu = page.getByRole("button", { name: "Screenshot" });
  const heading = page.getByRole("heading", { level: 1 });
  await accountMenu.or(heading).first().waitFor({ timeout: 15_000 });
  if (!(await accountMenu.isVisible())) return;
  await page.evaluate(() => localStorage.setItem("kaizen.theme", "system"));
  await accountMenu.click();
  await page.getByRole("menuitem", { name: "Log out" }).click();
  await page.waitForURL(/\/login/, { timeout: 15_000 });
  await page.goto(new URL(route, page.url()).href, { waitUntil: "domcontentloaded" });
}
```

- [ ] **Step 3: Replace the theme-open scenario with account-menu**

```bash
git rm frontend/scripts/screenshots/theme-open.mjs
```

Create `frontend/scripts/screenshots/account-menu.mjs`:

```js
// The header's account menu, open: the display name button reveals Request a feature, Pipeline,
// and Log out, so their icons and order can be compared in both themes; it also shows the icon-only
// theme control beside it and the whole header (brand, primary nav, truncated display name).
// Replaces theme-open, whose dropdown-menu the theme control no longer is.
export const route = "/tasks";

export async function ready(page) {
  await page.getByRole("heading", { name: "Tasks", level: 1 }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Screenshot" }).waitFor({ timeout: 15_000 });
}

export async function act(page) {
  await page.getByRole("button", { name: "Screenshot" }).click();
  await page.getByRole("menuitem", { name: "Log out" }).waitFor({ timeout: 5_000 });
}
```

- [ ] **Step 4: Fix the one stale example in ui-conventions.md**

In `frontend/docs/ui-conventions.md`, apply this diff:

```diff
-- Keep the accessible name a user reads out loud: "Log out", "Accept", "Theme". Names listed in
+- Keep the accessible name a user reads out loud: "Log out", "Accept", "Theme: Light". Names listed in
```

- [ ] **Step 5: Update the selector-contract table in README.md**

In `frontend/README.md`, apply this diff to the "Selector contract" table:

```diff
-| Anywhere  | log out          | button "Log out"                                                                                                                                                                                                                                                                                                                  |
+| Anywhere  | account menu     | button named by the display name opens a menu with menuitem "Log out" (and, only when their flags are on, menuitem "Request a feature" and menuitem "Pipeline")                                                                                                                                                                |
+| Anywhere  | log out          | menuitem "Log out", inside the account menu                                                                                                                                                                                                                                                                                      |
```

And update line 117's note (link Pipeline is now a menu item, not a link):

```diff
-Available to the smoke test but not yet required by it: link "Pipeline", heading "Pipeline", table
+Available to the smoke test but not yet required by it: menuitem "Pipeline" (inside the account
+menu), heading "Pipeline", table
 "Issues", buttons "Deploy to staging" and "Deploy <version> to production", and the dialog's field
 "Deploy passphrase" (`/pipeline`, shown only when health reports `features.pipeline: true`).
```

- [ ] **Step 6: CHANGELOG entry**

In `frontend/CHANGELOG.md`, add under `## [Unreleased]`:

```markdown
## [Unreleased]

### Changed

- The header's theme control is a single icon-only button that cycles light, dark, then system on
  each click (was a three-item menu); Feature Request, Pipeline, and Log out move into a new
  account menu opened from the display name, which is now always visible (was hidden below `xl`).
  `FeatureRequestLink` and `PipelineLink` are retired. Screenshot scenario `account-menu` replaces
  `theme-open`. #29
```

- [ ] **Step 7: Regenerate the product map**

```bash
cd frontend
npm run product-map
git diff --stat docs/product-map.md
```

Expected: the "App shell" table's `ThemeToggle`, `FeatureRequestLink`, and `PipelineLink` rows update to reflect `AccountMenu` and the retired files, deterministically from the current checkout.

- [ ] **Step 8: Capture the screenshots**

Start the local stack (Postgres and Redis running, then in the `backend/` checkout `nvm use && npm run dev` on port 3000), then here:

```bash
cd frontend
nvm use
VITE_PROXY_TARGET=http://localhost:3000 npm run dev &
sleep 3
node scripts/screenshot.mjs account-menu
```

Expected: `docs/screenshots/account-menu-light.png` and `docs/screenshots/account-menu-dark.png` are written. If it exits 2, it prints exactly one line, `Screenshot unavailable: <reason>` — stop, fix what it names (dev stack not up, Chrome missing), and retry; never fabricate the images.

Stop the dev server once the capture finishes.

- [ ] **Step 9: Look at the screenshots**

Open both PNGs with the Read tool. Compare against the spec's "Looks" section: icon-only theme button (no visible label) beside an `outline` button showing the display name and a chevron; the open menu lists Request a feature, Pipeline, a separator, then Log out, each with its icon; both themes use existing tokens, no new colors. A mismatch here is a code change (back to Task 2), not a caption change.

- [ ] **Step 10: The final gate and commit**

```bash
cd frontend
nvm use
npm test
npm run typecheck
npm run lint
git add -A
git commit -m "docs: header screenshots, changelog, product map, and screenshot-runner fixes (#29)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected: `npm test`, `npm run typecheck`, `npm run lint` all exit 0; the docs-check's last line is `docs-check: OK`. If it fails, fix the docs it names and amend this commit.

---

## Self-review

**Spec coverage:** "What"/"Behavior" → Tasks 1–2. "Acceptance criteria restated as tests" 1–3 → `ThemeToggle.test.tsx` (Task 1). Additional tests 4–7 → `AccountMenu.test.tsx`, `router.test.tsx`, `auth.test.tsx` (Task 2). "Out of scope" is respected (no auth/API/contract change anywhere in the plan). "Looks" → Task 3, Step 9's comparison. "Repos and files touched" all appear across the three tasks, plus the two screenshot helpers and the ui-conventions line the exploration surfaced, which the spec's file list did not originally name but which the rename mechanically requires.

**Placeholder scan:** none found — every step carries real, complete code or an exact diff.

**Type consistency:** `AccountMenu({ displayName }: { displayName: string })` in Task 2 Step 3 matches its call site in `layout.tsx` (`<AccountMenu displayName={user?.displayName ?? ""} />`) in the same step. `ThemeToggle`'s export name and zero-argument signature are unchanged from Task 1 through `layout.tsx`. `useFeatureRequestAvailable`/`usePipelineAvailable`'s `{ available: boolean | undefined }` shape (already defined in the untouched `hooks.ts` files) is used the same way `AccountMenu` and its test do.
