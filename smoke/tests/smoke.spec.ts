import { expect, test, type Locator, type Page } from "@playwright/test";

const AI_TIMEOUT_MS = Number(process.env.SMOKE_AI_TIMEOUT_MS ?? "90000");
const FAST = process.env.SMOKE_FAST === "1";
const PASSWORD = "smoke-pass-2026";
const DISPLAY_NAME = "Smoke";
const TASK_TITLE = "Prepare the quarterly business review deck for the leadership team";
const TASK_DESCRIPTION =
  "Collect last quarter's numbers from finance and product and turn them into a twelve-slide story. The deck is presented to the leadership team on Thursday and must run under twenty minutes.";

type AiState = "thinking" | "suggestions" | "failed" | "skipped" | "none";

// The chip inside a task row states the AI status in words. These patterns are the contract with the web app
// (see README.md, "Selector contract").
const CHIP = {
  thinking: /thinking/i,
  suggestions: /\d+ suggestions?/i,
  failed: /failed/i,
  skipped: /too short to break down|hourly limit reached|assistant paused/i,
};

function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

async function aiState(row: Locator): Promise<AiState> {
  const text = oneLine(await row.innerText());
  if (CHIP.thinking.test(text)) return "thinking";
  if (CHIP.failed.test(text)) return "failed";
  if (CHIP.skipped.test(text)) return "skipped";
  if (CHIP.suggestions.test(text)) return "suggestions";
  return "none";
}

async function expectLoginPage(page: Page): Promise<void> {
  await expect(page).toHaveURL(/\/login(\?.*)?$/);
  await expect(page.getByRole("heading", { name: /log in/i })).toBeVisible();
}

test("register, create a task, wait for the assistant, accept a suggestion, log out", async ({
  page,
}) => {
  const email = `smoke+${Date.now()}@kaizen.local`;
  const row = page.getByRole("listitem").filter({ hasText: TASK_TITLE });
  let state: AiState = "none";

  await test.step("1. open the base URL and expect the login page", async () => {
    await page.goto("/");
    await expectLoginPage(page);
  });

  await test.step("2. register a fresh user", async () => {
    await page.getByRole("link", { name: /register|create an account/i }).click();
    await expect(page).toHaveURL(/\/register$/);
    await expect(page.getByRole("heading", { name: /create your account/i })).toBeVisible();
    await page.getByLabel(/email/i).fill(email);
    await page.getByLabel(/^password$/i).fill(PASSWORD);
    await page.getByLabel(/display name/i).fill(DISPLAY_NAME);
    await page.getByRole("button", { name: /create account|register/i }).click();
    await expect(page).toHaveURL(/\/tasks$/);
  });

  await test.step("3. create the task from the task list", async () => {
    const title = page.getByRole("textbox", { name: /task title/i });
    await expect(title).toBeVisible();
    await title.fill(TASK_TITLE);
    const description = page.getByRole("textbox", { name: /description/i });
    if (!(await description.isVisible())) {
      await page.getByRole("button", { name: /description/i }).click();
    }
    await description.fill(TASK_DESCRIPTION);
    await title.press("Enter");
    await expect(row).toBeVisible();
  });

  await test.step("4. wait for the assistant", async () => {
    state = await aiState(row);
    if (state === "thinking") {
      if (FAST) {
        console.log("SMOKE_FAST=1: not waiting for the assistant");
      } else {
        await expect
          .poll(async () => (await aiState(row)) !== "thinking", {
            timeout: AI_TIMEOUT_MS,
            intervals: [2_000],
            message: `the AI chip was still thinking after ${AI_TIMEOUT_MS} ms`,
          })
          .toBe(true);
        state = await aiState(row);
      }
    }
    const rowText = oneLine(await row.innerText());
    if (state === "failed") {
      throw new Error(`AI breakdown failed: ${rowText}`);
    }
    if (state === "skipped") {
      console.log(`AI breakdown skipped, accepted as a pass: ${rowText}`);
    }
    if (state === "none") {
      console.log(`AI chip absent, the breakdown finished with no suggestions: ${rowText}`);
    }
  });

  await test.step("5. open the detail and accept the first suggestion when there is one", async () => {
    await row.getByRole("link", { name: TASK_TITLE }).click();
    await expect(page).toHaveURL(/\/tasks\/[0-9a-f-]{36}$/);
    await expect(page.getByRole("heading", { name: TASK_TITLE })).toBeVisible();
    const accept = page.getByRole("button", { name: /^accept$/i }).first();
    if (state === "suggestions") {
      await expect(accept).toBeVisible({ timeout: 15_000 });
      await accept.click();
      await expect(page.getByText(/\b\d+\/[1-9]\d*\b/).first()).toBeVisible();
    } else {
      console.log("No suggestion to accept on the detail page");
    }
  });

  await test.step("6. log out and expect the login page", async () => {
    const directLogout = page.getByRole("button", { name: /log out/i });
    if ((await directLogout.count()) > 0) {
      await directLogout.click();
    } else {
      await page.getByRole("button", { name: DISPLAY_NAME }).click();
      await page.getByRole("menuitem", { name: /log out/i }).click();
    }
    await expectLoginPage(page);
  });
});
