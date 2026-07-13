import { writeFile } from "node:fs/promises";
import { expect, test, devices } from "@playwright/test";

test.use({ ...devices["iPhone 14"] });

test("mobile review workspace renders and persists notes", async ({ page }) => {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });

  await page.goto("http://127.0.0.1:4173/", {
    waitUntil: "networkidle",
  });

  await page.screenshot({
    path: "test-results/mobile-loaded.png",
    fullPage: true,
  });
  await writeFile("test-results/mobile-loaded.html", await page.content());
  await writeFile(
    "test-results/browser-errors.json",
    JSON.stringify({ pageErrors, consoleErrors }, null, 2),
  );

  const appHome = page.getByRole("link", {
    name: /LindaData Sports home/i,
  });
  await expect(appHome).toBeVisible();

  const notesButton = page.getByRole("button", { name: /open review notebook/i });
  await expect(notesButton).toBeVisible();

  await notesButton.click();
  const notebook = page.getByRole("complementary", { name: /review notebook/i });
  await expect(notebook).toBeVisible();

  const pageNote = page.getByRole("textbox", { name: /page note/i });
  await pageNote.fill("Mobile visual smoke test");

  await page.getByRole("link", { name: /matches/i }).last().click();
  await expect(appHome).toBeVisible();
  await expect(notebook).toBeVisible();

  await page.goto("http://127.0.0.1:4173/", {
    waitUntil: "networkidle",
  });
  await page.getByRole("button", { name: /open review notebook/i }).click();
  await expect(page.getByRole("textbox", { name: /page note/i })).toHaveValue(
    "Mobile visual smoke test",
  );

  await page.screenshot({
    path: "test-results/mobile-notebook.png",
    fullPage: true,
  });

  expect(pageErrors).toEqual([]);
  expect(consoleErrors).toEqual([]);
});
