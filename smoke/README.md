# Kaizen Tasks smoke test

One Playwright test, Chromium only, run against a deployed Kaizen Tasks web URL. Both app repos check this repository out at `main` in their `promote` workflow and run it against staging before a pull request into `main` may merge.

## What it does, in order

1. Opens the base URL and expects the login page.
   1b. Reads `GET /api/v1/health` and expects the footer (`role contentinfo`) to print that version and the API's short commit. Land the app change on staging before promoting this step to `main`, or both promote gates fail.
2. Registers `smoke+<timestamp>@kaizen.local` with a fixed password and the display name "Smoke".
3. Expects the task list and creates the task "Prepare the quarterly business review deck for the leadership team" with a two-sentence description.
4. Expects the row with a thinking chip. Unless fast mode, polls the row until the chip leaves thinking, within the AI timeout. Fails on a failed chip or on timeout. Accepts a skipped chip as a pass with a console note.
5. Opens the detail. If the row's chip showed suggestions in step 4, waits for the Accept button to appear, accepts the first suggestion, and expects the progress label to read `0/1` or higher. Otherwise logs that there was no suggestion to accept.
6. Logs out and expects the login page.

## Run it

```bash
nvm use
npm ci
npx playwright install --with-deps chromium
SMOKE_BASE_URL=https://<web domain> npm test          # headless
SMOKE_BASE_URL=http://localhost:5173 npm run test:headed   # rehearsal, watch it
```

| Variable              | Required | Default | Meaning                                      |
| --------------------- | -------- | ------- | -------------------------------------------- |
| `SMOKE_BASE_URL`      | yes      | none    | The web app origin                           |
| `SMOKE_AI_TIMEOUT_MS` | no       | `90000` | How long to wait for the assistant to finish |
| `SMOKE_FAST`          | no       | unset   | `1` skips the AI wait (step 4)               |

Traces and screenshots are written under `test-results/` on failure, plus an HTML report under `playwright-report/`. Open a trace with `npx playwright show-trace test-results/<folder>/trace.zip`.

## Selector contract

The test finds elements by accessible role and name, never by CSS class. The web app must satisfy:

| Screen    | Element          | Locator used                                                                                                                                                                                             |
| --------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Login     | heading          | role heading, name matches `/log in/i`; URL ends in `/login`                                                                                                                                             |
| Login     | link to register | role link, name matches `/register\|create an account/i`                                                                                                                                                 |
| Register  | heading          | role heading, name matches `/create your account/i`; awaited before filling the form so a React Router transition can't leave the login form's fields under the same locators                            |
| Register  | inputs           | labels matching `/email/i`, `/^password$/i`, `/display name/i`                                                                                                                                           |
| Register  | submit           | role button, name matches `/create account\|register/i`; success lands on `/tasks`                                                                                                                       |
| Task list | create bar       | role textbox named `Task title`; role textbox named `Description` (a button whose name contains "description" reveals it when collapsed); Enter in the title submits                                     |
| Task list | row              | role listitem containing the task title; the title is a link to the detail                                                                                                                               |
| Task list | AI chip text     | `Thinking` while pending or running; `N suggestions` when done with suggestions; contains `failed` on failure; one of `too short to break down`, `hourly limit reached`, `assistant paused` when skipped |
| Detail    | heading          | role heading with the task title; URL `/tasks/<uuid>`                                                                                                                                                    |
| Detail    | accept           | role button named exactly `Accept` on each suggested step                                                                                                                                                |
| Detail    | progress         | text matching `done/total`, for example `0/1`                                                                                                                                                            |
| Anywhere  | log out          | role button named `Log out`, or a role button named after the display name that opens a menu with a menuitem `Log out`                                                                                   |

## How the app repos call it

```yaml
- uses: actions/checkout@v5
  with:
    repository: kpnemo/kaizen-tasks-assembly-line
    ref: main
    path: assembly-line
- uses: actions/setup-node@v5
  with:
    node-version-file: .nvmrc
- run: npm ci
  working-directory: assembly-line/smoke
- run: npx playwright install --with-deps chromium
  working-directory: assembly-line/smoke
- run: npm test
  working-directory: assembly-line/smoke
  env:
    SMOKE_BASE_URL: https://web-staging-52c0.up.railway.app
    SMOKE_AI_TIMEOUT_MS: "180000"
- uses: actions/upload-artifact@v5
  if: failure()
  with:
    name: smoke-results
    path: assembly-line/smoke/test-results/
```

The repository is public, so the checkout needs no token (verification item L3 in the assembly-line spec, proven by the first `promote` run; fallback: pass `token: ${{ github.token }}` with read scope).
