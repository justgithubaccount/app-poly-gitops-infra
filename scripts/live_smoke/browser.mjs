import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { writeFile } from "node:fs/promises";

const [ui, output] = process.argv.slice(2);
const require = createRequire(`${ui}/package.json`);
const { chromium, expect } = require("@playwright/test");
const base = "http://127.0.0.1:3101";
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || undefined });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
const traces = [];
page.on("pageerror", (error) => errors.push(error.message));

async function sendChat(text, expected) {
  await page.getByLabel("Сообщение", { exact: true }).fill(text);
  await page.getByRole("button", { name: "Отправить", exact: true }).click();
  await expect(page.getByText(expected, { exact: true })).toBeVisible({ timeout: 70000 });
}

try {
  await page.goto(base);
  await page.getByLabel("Название проекта").fill("Live OpenAI UI smoke");
  const createdResponse = page.waitForResponse((response) =>
    response.request().method() === "POST" && new URL(response.url()).pathname === "/api/backend/projects");
  await page.getByRole("button", { name: "Создать проект", exact: true }).click();
  const created = await (await createdResponse).json();
  await page.locator(`a[href="/projects/${created.id}"]`).click();
  await sendChat("Reply with exactly LIVE_PROJECT_OK and no other text.", "LIVE_PROJECT_OK");
  await page.getByText("История запросов проекта", { exact: true }).click();
  const history = await (await fetch(`${base}/api/backend/projects/${created.id}/history`)).json();
  assert.equal(history.length, 1);
  assert.match(history[0].trace_id, /^[0-9a-f]{32}$/);
  traces.push({ service: "chat-api-live-smoke", trace_id: history[0].trace_id });
  await expect(page.getByText(`trace_id: ${history[0].trace_id}`, { exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByText("LIVE_PROJECT_OK", { exact: true })).toHaveCount(0);
  await page.getByText("История запросов проекта", { exact: true }).click();
  await expect(page.getByText(/user: Reply with exactly LIVE_PROJECT_OK/)).toBeVisible();

  await page.goto(`${base}/chat`);
  await sendChat("Reply with exactly LIVE_FASTAPI_OK and no other text.", "LIVE_FASTAPI_OK");

  await page.goto(`${base}/automation`);
  await expect(page.getByText("CrewAI отвечает: ok", { exact: true })).toBeVisible();
  await expect(page.getByRole("list", { name: "Агенты" }).locator("li")).toHaveCount(9);
  await expect(page.getByRole("list", { name: "Доступные flows" })).toContainText("live-llm-smoke");
  const runs = [];
  for (const flow of ["", "live-llm-smoke"]) {
    await page.getByLabel("Flow", { exact: true }).selectOption(flow);
    await page.getByLabel("Namespace", { exact: true }).fill("synthetic-smoke");
    await page.getByLabel("Контекст (JSON)", { exact: true }).fill(JSON.stringify({
      raw_kubectl_output: "synthetic-smoke smoke-pod-a 1/1 Running 2m node-test",
      instruction: "This is synthetic input, not a real cluster. Give one sentence under 30 words. Include LIVE_CREWAI_OK.",
    }));
    await page.getByRole("checkbox", { name: /Понимаю, что flow/ }).check();
    const completed = page.waitForResponse((response) =>
      response.request().method() === "POST" && new URL(response.url()).pathname.startsWith("/api/automation/run"),
    { timeout: 90000 });
    await page.getByRole("button", { name: "Запустить flow", exact: true }).click();
    const response = await completed;
    assert.equal(response.status(), 200, await response.text());
    const run = await response.json();
    assert.equal(run.steps.length, 1);
    assert.equal(run.steps[0].task, "explain_pods");
    assert.equal(run.steps[0].agent, "reporting_analyst");
    assert.ok(run.final_answer.trim());
    assert.match(run.metadata.trace_id, /^[0-9a-f]{32}$/);
    traces.push({ service: "crewai-live-smoke", trace_id: run.metadata.trace_id });
    await expect(page.getByRole("list", { name: "Шаги выполнения" }).locator("li")).toHaveCount(1);
    await expect(page.getByText(`trace_id: ${run.metadata.trace_id}`, { exact: true })).toBeVisible();
    await expect(page.getByRole("checkbox", { name: /Понимаю, что flow/ })).not.toBeChecked();
    runs.push({ route: flow ? "named" : "server-default", steps: 1 });
  }
  assert.deepEqual(errors, []);
  await writeFile(`${output}/browser.json`, JSON.stringify({
    result: "PASS", project_create: true, project_chat: true,
    persisted_request_history: true, assistant_reply_not_falsely_restored: true,
    quick_chat: true, crewai_agents: 9, crewai_runs: runs, traces, page_errors: errors,
  }));
} finally {
  await browser.close();
}
