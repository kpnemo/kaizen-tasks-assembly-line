import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.SMOKE_BASE_URL;
if (!baseURL) {
  throw new Error(
    "SMOKE_BASE_URL is required, for example SMOKE_BASE_URL=https://web-staging-52c0.up.railway.app",
  );
}
const aiTimeoutMs = Number(process.env.SMOKE_AI_TIMEOUT_MS ?? "90000");
if (!Number.isFinite(aiTimeoutMs) || aiTimeoutMs <= 0) {
  throw new Error(
    `SMOKE_AI_TIMEOUT_MS must be a positive number of milliseconds, got ${process.env.SMOKE_AI_TIMEOUT_MS}`,
  );
}

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  // The single test waits up to aiTimeoutMs for the assistant plus about two minutes of navigation.
  timeout: aiTimeoutMs + 120_000,
  expect: { timeout: 15_000 },
  outputDir: "test-results",
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "off",
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
