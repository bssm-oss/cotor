package com.cotor.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.io.path.createDirectories
import kotlin.io.path.readText
import kotlin.io.path.writeText

class LocalPlaywrightMarketingBrowserRunner(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() },
    private val commandAvailability: (String) -> Boolean = ::defaultMarketingCommandAvailability
) : MarketingBrowserRunner {
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    override suspend fun execute(command: MarketingBrowserCommand, timeoutSeconds: Int): MarketingBrowserResult {
        require(commandAvailability("npx")) {
            "Marketing browser execution requires npx so Cotor can run Playwright without storing browser credentials."
        }
        val runtimeDir = appHomeProvider().resolve("runtime").resolve("marketing").resolve(command.runId)
        runtimeDir.createDirectories()
        val inputPath = runtimeDir.resolve("${command.actionId}.json")
        val scriptPath = runtimeDir.resolve("marketing-operator-playwright.mjs")
        val stderrPath = runtimeDir.resolve("${command.actionId}.stderr.log")
        inputPath.writeText(json.encodeToString(MarketingBrowserCommand.serializer(), command))
        scriptPath.writeText(marketingPlaywrightScript)
        val process = withContext(Dispatchers.IO) {
            ProcessBuilder(
                "npx",
                "--yes",
                "--package=playwright",
                "node",
                scriptPath.toString(),
                inputPath.toString()
            )
                .redirectError(stderrPath.toFile())
                .start()
        }
        val stdout = withTimeout(timeoutSeconds.coerceAtLeast(5) * 1000L) {
            withContext(Dispatchers.IO) {
                val completed = process.waitFor(timeoutSeconds.coerceAtLeast(5).toLong(), TimeUnit.SECONDS)
                if (!completed) {
                    process.destroyForcibly()
                    error("Marketing browser execution timed out after ${timeoutSeconds.coerceAtLeast(5)}s.")
                }
                val output = process.inputStream.bufferedReader().readText()
                if (process.exitValue() != 0) {
                    val stderr = runCatching { stderrPath.readText() }.getOrDefault("")
                    error("Marketing browser execution failed: ${stderr.ifBlank { output }.take(600)}")
                }
                output
            }
        }
        return json.decodeFromString(MarketingBrowserResult.serializer(), stdout.trim())
    }
}

private fun defaultMarketingCommandAvailability(command: String): Boolean =
    System.getenv("PATH")
        ?.split(java.io.File.pathSeparator)
        ?.map { Path.of(it).resolve(command) }
        ?.any { Files.isExecutable(it) }
        ?: false

private val marketingPlaywrightScript = """
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const inputPath = process.argv[2];
const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
fs.mkdirSync(path.dirname(input.screenshotPath), { recursive: true });

const launchOptions = { headless: true };
const browser = await chromium.launch(launchOptions);
const contextOptions = {};
if (input.browserSessionRef && fs.existsSync(input.browserSessionRef)) {
  contextOptions.storageState = input.browserSessionRef;
}
const context = await browser.newContext(contextOptions);
const page = await context.newPage();
try {
  await page.goto(input.targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const title = `${'$'}{input.channel}: ${'$'}{input.objective}`.slice(0, 120);
  const body = [
    input.objective,
    input.brandTone ? `Tone: ${'$'}{input.brandTone}` : '',
    `Idempotency: ${'$'}{input.idempotencyKey}`
  ].filter(Boolean).join('\n\n');

  for (const selector of ['[name="title"]', '#title', '[data-cotor-field="title"]']) {
    const count = await page.locator(selector).count().catch(() => 0);
    if (count > 0) {
      await page.locator(selector).first().fill(title);
      break;
    }
  }
  for (const selector of ['[name="body"]', '#body', 'textarea', '[contenteditable="true"]', '[data-cotor-field="body"]']) {
    const count = await page.locator(selector).count().catch(() => 0);
    if (count > 0) {
      await page.locator(selector).first().fill(body);
      break;
    }
  }

  const publishSelectors = [
    '[data-cotor-action="publish"]',
    'button[type="submit"]',
    'input[type="submit"]',
    'text=/^(Publish|Post|Save|Submit|게시|발행)$/i'
  ];
  let clicked = false;
  for (const selector of publishSelectors) {
    const locator = page.locator(selector).first();
    const count = await locator.count().catch(() => 0);
    if (count > 0) {
      await Promise.allSettled([
        page.waitForLoadState('networkidle', { timeout: 5000 }),
        locator.click({ timeout: 5000 })
      ]);
      clicked = true;
      break;
    }
  }
  if (!clicked) {
    throw new Error('No publish control found in the delegated browser page.');
  }
  await page.screenshot({ path: input.screenshotPath, fullPage: true });
  console.log(JSON.stringify({
    postedUrl: page.url(),
    screenshotPath: input.screenshotPath,
    inputSummary: `${'$'}{input.channel} publish form filled from objective`,
    outputSummary: `Published through browser automation at ${'$'}{page.url()}`
  }));
} finally {
  await context.close();
  await browser.close();
}
""".trimIndent()
