# Accent colour from indigo to oxblood (#19) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one `--brand` CSS variable the app's accent, set it to oxblood, derive every accent token in both themes from it, and pin the two files that cannot read CSS to its hex.

**Architecture:** The accent already flows through five shadcn tokens in `frontend/src/styles/globals.css`, mapped to Tailwind utilities by the `@theme inline` block, so every button, link, checkbox, badge and focus ring follows the tokens. This plan adds `--brand` and rewrites the nine accent token values as relative-colour derivations of it. A file-level Vitest test guards the shape (one brand, all accent tokens derived, no indigo left, theme-color meta and favicon at the brand's hex). Screenshots prove the look in both themes.

**Tech Stack:** Vite 7, React 19, Tailwind 4 (Lightning CSS), Vitest, Node 24 via `nvm use`, `scripts/screenshot.mjs` (playwright-core driving installed Chrome).

**Spec:** `docs/superpowers/specs/2026-09-10-issue-19-change-app-accent-color-from-blue-to-dar.md`

## Global Constraints

- Web repo only: `frontend/` (kpnemo/kaizen-tasks-web), branch `feat/19-change-app-accent-color-from-blue-to-dar`, already checked out. No API change, no ADR (no architectural file changes).
- `--brand: oklch(0.42 0.13 30)` declared exactly once, in `:root`. Derived tokens use `var(--brand)` or `oklch(from var(--brand) <L> calc(c * <factor>) h)` with the factors in the spec's table.
- Neutral grays, backgrounds, `--destructive` and `src/lib/tag-palette.ts` stay byte-for-byte as they are.
- Theme-color meta in `index.html` and the tile fill in `public/favicon.svg` are `#86281d`.
- Every commit ends with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Every npm command runs inside `frontend/` after `nvm use`. Never `npm run docs:check` (hook mode); the gate is `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci`, last line `docs-check: OK`.
- Follow `frontend/.claude/skills/add-frontend-feature/SKILL.md`: criteria restated, failing test shown, docs before the green run, `npm run product-map`, tests, lint, typecheck, screenshots for a visible change.

---

### Task 1: The brand variable, the derived tokens, the test and the docs

Skill: `frontend/.claude/skills/add-frontend-feature/SKILL.md` (steps 1, 3, 4, 7, 8, 9).

**Files:**
- Create: `frontend/tests/accent-tokens.test.ts`
- Modify: `frontend/src/styles/globals.css` (the identity comment, `:root` lines 14-32, `.dark` lines 36-56)
- Modify: `frontend/index.html` (the `theme-color` meta, line 29)
- Modify: `frontend/public/favicon.svg` (the `<rect>` fill)
- Modify: `frontend/CHANGELOG.md` (`[Unreleased]`, new `### Changed`), `frontend/README.md` (Features list), `frontend/docs/product-map.md` (regenerated)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `--brand` in `:root`; the resolved oxblood set Task 2 photographs.

- [ ] **Step 1: Write the failing test**

`frontend/tests/accent-tokens.test.ts`:

```ts
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// The accent is one CSS variable, `--brand`, and every accent token derives from it (issue #19).
// Vitest runs with `css: false`, so these assertions read the source files as text, the way
// tests/product-map.test.ts reads router.tsx.

const ROOT = new URL("..", import.meta.url).pathname;
const read = (path: string) => readFileSync(join(ROOT, path), "utf8");
const css = read("src/styles/globals.css");

/** The declarations inside the top-level `<selector> {` block. Neither block nests braces. */
function block(selector: string): string {
  const start = css.indexOf(`\n${selector} {`);
  if (start === -1) throw new Error(`no ${selector} block in globals.css`);
  const open = css.indexOf("{", start);
  return css.slice(open + 1, css.indexOf("}", open));
}

function token(selector: string, name: string): string {
  const match = block(selector).match(new RegExp(`--${name}:\\s*([^;]+);`));
  if (!match) throw new Error(`no --${name} in ${selector}`);
  return match[1].trim();
}

/** oklch → sRGB hex, the same conversion Lightning CSS applies when it lowers the literal. */
function oklchToHex(L: number, C: number, h: number): string {
  const a = C * Math.cos((h * Math.PI) / 180);
  const b = C * Math.sin((h * Math.PI) / 180);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const channel = (x: number) => {
    const clamped = Math.max(0, Math.min(1, x));
    const gamma = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * clamped ** (1 / 2.4) - 0.055;
    return Math.round(gamma * 255)
      .toString(16)
      .padStart(2, "0");
  };
  return (
    "#" +
    channel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s) +
    channel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s) +
    channel(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)
  );
}

const ACCENT_TOKENS = ["primary", "accent", "accent-foreground", "ring"];
const DERIVED = /^(var\(--brand\)|oklch\(from var\(--brand\) [\d.]+ calc\(c \* [\d.]+\) h\))$/;

describe("accent tokens", () => {
  it("declares the brand accent once, as oxblood", () => {
    expect(token(":root", "brand")).toBe("oklch(0.42 0.13 30)");
    expect(css.match(/--brand:/g)).toHaveLength(1);
  });

  it("derives every accent token in both themes from the brand", () => {
    for (const name of ACCENT_TOKENS) {
      expect(token(":root", name), `:root --${name}`).toMatch(DERIVED);
      expect(token(".dark", name), `.dark --${name}`).toMatch(DERIVED);
    }
    expect(token(".dark", "primary-foreground")).toMatch(DERIVED);
    expect(token(":root", "primary-foreground")).toBe("oklch(0.99 0 0)");
  });

  it("keeps the indigo hue out of the accent and leaves the neutrals and the destructive red alone", () => {
    for (const selector of [":root", ".dark"]) {
      for (const name of [...ACCENT_TOKENS, "primary-foreground"]) {
        expect(token(selector, name), `${selector} --${name}`).not.toMatch(/ 272\)/);
      }
    }
    expect(token(":root", "background")).toBe("oklch(0.985 0.005 95)");
    expect(token(":root", "foreground")).toBe("oklch(0.2 0.02 270)");
    expect(token(".dark", "background")).toBe("oklch(0.19 0.02 270)");
    expect(token(":root", "destructive")).toBe("oklch(0.55 0.2 27)");
    expect(token(".dark", "destructive")).toBe("oklch(0.68 0.19 27)");
  });

  it("paints the primary button, the checked checkbox, links and the focus ring with the tokens", () => {
    const button = read("src/components/ui/button.tsx");
    expect(button).toMatch(/default: "bg-primary text-primary-foreground/);
    expect(button).toMatch(/link: "text-primary/);
    expect(read("src/components/ui/checkbox.tsx")).toContain("data-[state=checked]:bg-primary");
    expect(css).toMatch(/:focus-visible \{\s*outline: 3px solid var\(--ring\);/);
    for (const page of [
      "src/features/auth/LoginPage.tsx",
      "src/features/auth/RegisterPage.tsx",
      "src/features/tasks/TaskDetailPage.tsx",
      "src/app/routes/NotFoundPage.tsx",
    ]) {
      expect(read(page), page).toContain("text-primary underline");
    }
  });

  it("hard-codes no blue anywhere under src", () => {
    const files: string[] = [];
    const walk = (dir: string) => {
      for (const entry of readdirSync(dir)) {
        const path = join(dir, entry);
        if (statSync(path).isDirectory()) walk(path);
        else if (/\.(tsx?|css|html)$/.test(entry)) files.push(path);
      }
    };
    walk(join(ROOT, "src"));
    files.push(join(ROOT, "index.html"));
    const skipped = [join(ROOT, "src/api/"), join(ROOT, "src/lib/tag-palette")];
    for (const file of files) {
      if (skipped.some((prefix) => file.startsWith(prefix))) continue;
      const text = readFileSync(file, "utf8");
      expect(text, file).not.toMatch(/\b(blue|indigo|sky)-\d{2,3}\b/);
      expect(text.toLowerCase(), file).not.toContain("#4744b8");
    }
  });

  it("carries the brand as hex in the browser theme-color and the favicon", () => {
    const match = token(":root", "brand").match(/^oklch\(([\d.]+) ([\d.]+) ([\d.]+)\)$/);
    if (!match) throw new Error("--brand is not a literal oklch(L C h)");
    const hex = oklchToHex(Number(match[1]), Number(match[2]), Number(match[3]));
    expect(hex).toBe("#86281d");
    expect(read("index.html")).toContain(`<meta name="theme-color" content="${hex}" />`);
    expect(read("public/favicon.svg")).toContain(`fill="${hex}"`);
  });
});
```

- [ ] **Step 2: Run it and watch it fail for the right reason**

Run, in `frontend/` after `nvm use`: `npx vitest run tests/accent-tokens.test.ts`
Expected: 4 failed, 2 passed. "declares the brand accent once" fails with `no --brand in :root`; "derives every accent token" fails with `no --brand in :root`; "keeps the indigo hue out" fails because `--primary` in `:root` is `oklch(0.45 0.19 272)`; "carries the brand as hex" fails with `no --brand in :root`. The two guards ("paints the primary button…", "hard-codes no blue…") pass already, which is what a guard should do.

- [ ] **Step 3: Rewrite the tokens in `globals.css`**

Replace the identity comment and the `:root` and `.dark` blocks (lines 10 to 57 today) so they read:

```css
/* Kaizen identity: one accent, one display face (Fraunces), one body face (Atkinson Hyperlegible),
   tuned for a projected laptop screen. The accent is `--brand` (oxblood); every accent token in both
   themes derives from it, so a refresh changes that one line. Two files cannot read a CSS variable
   and carry its hex by hand: the theme-color meta in index.html and the tile in public/favicon.svg.
   tests/accent-tokens.test.ts names the hex they must carry. */
:root {
  --brand: oklch(0.42 0.13 30);
  --background: oklch(0.985 0.005 95);
  --foreground: oklch(0.2 0.02 270);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.2 0.02 270);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.2 0.02 270);
  --primary: var(--brand);
  --primary-foreground: oklch(0.99 0 0);
  --secondary: oklch(0.94 0.01 95);
  --secondary-foreground: oklch(0.2 0.02 270);
  --muted: oklch(0.94 0.01 95);
  --muted-foreground: oklch(0.5 0.02 80);
  --accent: oklch(from var(--brand) 0.93 calc(c * 0.25) h);
  --accent-foreground: oklch(from var(--brand) 0.32 calc(c * 0.8) h);
  --destructive: oklch(0.55 0.2 27);
  --border: oklch(0.86 0.01 95);
  --input: oklch(0.86 0.01 95);
  --ring: var(--brand);
  --radius: 0.75rem;
  color-scheme: light;
}

/* The same identity after dark: the accent lifts so it still reads on a dark ground, and the
   neutrals keep their warm tilt. Only the tokens change; nothing below this knows. */
.dark {
  --background: oklch(0.19 0.02 270);
  --foreground: oklch(0.96 0.005 95);
  --card: oklch(0.24 0.02 270);
  --card-foreground: oklch(0.96 0.005 95);
  --popover: oklch(0.24 0.02 270);
  --popover-foreground: oklch(0.96 0.005 95);
  --primary: oklch(from var(--brand) 0.72 calc(c * 0.85) h);
  --primary-foreground: oklch(from var(--brand) 0.17 calc(c * 0.25) h);
  --secondary: oklch(0.3 0.02 270);
  --secondary-foreground: oklch(0.96 0.005 95);
  --muted: oklch(0.3 0.02 270);
  --muted-foreground: oklch(0.76 0.02 90);
  --accent: oklch(from var(--brand) 0.36 calc(c * 0.45) h);
  --accent-foreground: oklch(from var(--brand) 0.93 calc(c * 0.25) h);
  --destructive: oklch(0.68 0.19 27);
  --border: oklch(0.35 0.02 270);
  --input: oklch(0.35 0.02 270);
  --ring: oklch(from var(--brand) 0.72 calc(c * 0.85) h);
  color-scheme: dark;
}
```

Everything below `.dark` (the `@theme inline` block and `@layer base`) is untouched.

- [ ] **Step 4: Pin the two files that cannot read CSS**

`frontend/index.html`: change `<meta name="theme-color" content="#4744b8" />` to `<meta name="theme-color" content="#86281d" />`.
`frontend/public/favicon.svg`: change `fill="#4744b8"` to `fill="#86281d"` on the `<rect>`.

- [ ] **Step 5: Run the test and watch it pass**

Run: `npx vitest run tests/accent-tokens.test.ts`
Expected: 6 passed.

- [ ] **Step 6: Docs before the green run**

`frontend/CHANGELOG.md`, under `## [Unreleased]`, after the `### Added` list, add:

```markdown
### Changed

- The accent is oxblood instead of indigo, and it is one variable: `--brand` in `src/styles/globals.css` (`oklch(0.42 0.13 30)`), from which `--primary`, `--ring`, `--accent` and `--accent-foreground` derive in both themes with relative colour syntax. Primary buttons, links, the checked checkbox, the focus ring, the AI badges and chips, the progress bar and the brand mark follow it; neutrals, backgrounds, the destructive red and the tag palette do not change. The browser theme-color and the favicon tile carry its hex, `#86281d`, and `tests/accent-tokens.test.ts` keeps them in step with the variable. (#19)
```

`frontend/README.md`, in the `## Features` list, after the Theme bullet, add:

```markdown
- Brand accent: oxblood, declared once as `--brand` in `src/styles/globals.css`; every accent-coloured element in both themes derives from it, so changing that line refreshes the app (the theme-color meta and the favicon then take the hex the accent test prints)
```

Then run `npm run product-map` and keep the regenerated `docs/product-map.md`.

- [ ] **Step 7: Green run and format**

Run, in order: `npx prettier --write tests/accent-tokens.test.ts src/styles/globals.css CHANGELOG.md README.md index.html`, then `npm test`, `npm run lint`, `npm run typecheck`.
Expected: every command exits 0; `npm test` shows the new file's 6 tests passing alongside the existing suites (including `tests/product-map.test.ts`, which is why the map was regenerated first).

- [ ] **Step 8: Commit and run the docs gate**

```bash
git add -A
git commit -m "feat: accent from indigo to oxblood through one --brand variable (#19)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected: last line `docs-check: OK`. If it is not, fix the docs and `git commit --amend --no-edit`.

---

### Task 2: Screenshots of both themes

Skill: `frontend/.claude/skills/add-frontend-feature/SKILL.md` (step 11 and the Screenshots section).

**Files:**
- Modify: `frontend/docs/screenshots/tasks-light.png`, `tasks-dark.png`, `theme-focused-light.png`, `theme-focused-dark.png` (regenerated)

**Interfaces:**
- Consumes: the committed tokens from Task 1.
- Produces: the four PNGs and the commit SHA that pins them in the pull request body.

- [ ] **Step 1: Start the local stack**

Postgres (5432) and Redis (6379) are already listening. In two background processes:

```bash
cd backend && nvm use && npm run dev          # API on http://localhost:3000
cd frontend && nvm use && VITE_PROXY_TARGET=http://localhost:3000 npm run dev   # web on http://localhost:5173
```

Wait until `curl -s http://localhost:3000/api/v1/health` returns JSON and `curl -s -o /dev/null -w '%{http_code}' http://localhost:5173/` prints 200.

- [ ] **Step 2: Capture**

Run, in `frontend/`: `node scripts/screenshot.mjs tasks` then `node scripts/screenshot.mjs theme-focused`.
Expected: each writes `docs/screenshots/<name>-light.png` and `-dark.png` at 1280x800 and exits 0. If either exits 2, copy its one stderr line verbatim into the pull request body where the images would go and do not retry.

- [ ] **Step 3: Look at all four PNGs**

Open each with the Read tool and compare with the spec's `## Looks`: light shows a deep wine-brown primary control, brand mark and focus ring on a warm off-white ground; dark shows a dusty rose-brown accent on the cool dark ground; no indigo anywhere; neutrals unchanged. A mismatch is a token change in Task 1, not a caption change.

- [ ] **Step 4: Commit the images and stop the stack**

```bash
git add docs/screenshots
git commit -m "docs: screenshots of the oxblood accent in both themes (#19)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git log -1 --format=%H -- docs/screenshots     # the SHA the pull request body pins
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Then stop the two dev servers.

---

After Task 2, the push, the web pull request (with the `Part of` line, the criteria checklist, the failing and passing output and the commit-pinned screenshot URLs) and the docs pull request in this workspace repo follow `/implement-issue` Step 8; they are not plan tasks.

## Self-review

- Spec coverage: `--brand` once and the nine derivations (Task 1 step 3); theme-color and favicon (step 4); the six tests map to the spec's four effective criteria (step 1); docs and product map (step 6); Looks and screenshots (Task 2); out-of-scope items are asserted unchanged (test 3).
- Placeholders: none; every step carries its content.
- Consistency: the token names, factors and the hex `#86281d` are the same in the spec's table, the CSS in step 3 and the test in step 1.
