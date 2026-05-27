package com.cotor.app

import com.cotor.storage.writeTextAtomically
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.deleteIfExists
import kotlin.io.path.exists

class LocalPlaywrightMarketingBrowserRunner internal constructor(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() },
    private val commandAvailability: (String) -> Boolean = ::marketingCommandAvailable,
    private val processRunner: LocalSkillProcessRunner = defaultLocalSkillProcessRunner
) : MarketingBrowserRunner {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    override suspend fun execute(command: MarketingBrowserCommand): MarketingBrowserResult = withContext(Dispatchers.IO) {
        val runtimeRoot = appHomeProvider()
            .toAbsolutePath()
            .normalize()
            .resolve("runtime")
        val normalizedCommand = command.copy(
            screenshotPath = requireLocalBrowserRuntimeOutputPath(
                rawPath = command.screenshotPath,
                runtimeRoot = runtimeRoot,
                label = "screenshotPath"
            ).toString(),
            maxRuntimeSeconds = normalizeLocalBrowserRuntimeSeconds(
                command.maxRuntimeSeconds,
                MARKETING_BROWSER_MAX_RUNTIME_SECONDS
            )
        )
        require(commandAvailability("node") && commandAvailability("npm")) {
            "Marketing browser execution requires node and npm so Playwright can run without storing browser credentials in Cotor."
        }
        val runtimeDir = runtimeRoot
            .resolve("marketing-browser")
        val inputDir = runtimeDir.resolve("inputs")
        val scriptPath = runtimeDir.resolve("marketing-runner.js")
        runtimeDir.createDirectories()
        inputDir.createDirectories()
        // Install phase runs with its own 120s minimum and must not be capped by the run-phase timeout.
        ensurePlaywrightDependency(runtimeDir, normalizedCommand.maxRuntimeSeconds)
        writeTextAtomically(scriptPath, playwrightRunnerScript)
        val inputPath = Files.createTempFile(inputDir, "marketing-command-", ".json")
        try {
            writeTextAtomically(inputPath, json.encodeToString(MarketingBrowserCommand.serializer(), normalizedCommand))
            val timeoutSeconds = normalizedCommand.maxRuntimeSeconds.toLong()
            val result = processRunner.run(
                command = listOf("node", scriptPath.toString(), inputPath.toString()),
                workingDirectory = runtimeDir,
                timeoutSeconds = timeoutSeconds,
                timeoutMessage = "Marketing browser execution timed out after ${timeoutSeconds}s.",
                environment = mapOf("NODE_PATH" to runtimeDir.resolve("node_modules").toString())
            )
            val output = result.output.trim()
            if (result.exitCode != 0) {
                error(output.ifBlank { "Marketing browser execution failed with exit ${result.exitCode}." })
            }
            runCatching {
                json.decodeFromString(MarketingBrowserResult.serializer(), output.lines().last())
            }.getOrElse { error ->
                throw IllegalStateException(
                    "Marketing browser execution did not return a valid result: ${error.message}. Output: $output"
                )
            }
        } finally {
            inputPath.deleteIfExists()
        }
    }

    private suspend fun ensurePlaywrightDependency(runtimeDir: Path, timeoutSeconds: Int) {
        withLocalSkillRuntimeMutationLock(runtimeDir) {
            val packageDir = runtimeDir.resolve("node_modules").resolve("playwright")
            if (packageDir.exists()) {
                return@withLocalSkillRuntimeMutationLock
            }
            val installTimeoutSeconds = timeoutSeconds.coerceAtLeast(120).toLong()
            val result = processRunner.run(
                command = listOf(
                    "npm",
                    "install",
                    "--silent",
                    "--no-audit",
                    "--no-fund",
                    "--prefix",
                    runtimeDir.toString(),
                    "playwright"
                ),
                workingDirectory = runtimeDir,
                timeoutSeconds = installTimeoutSeconds,
                timeoutMessage = "Playwright dependency install timed out after ${installTimeoutSeconds}s.",
                environment = emptyMap()
            )
            val output = result.output.trim()
            if (result.exitCode != 0) {
                error(output.ifBlank { "Playwright dependency install failed with exit ${result.exitCode}." })
            }
        }
    }

    private val playwrightRunnerScript: String = """
        const fs = require("fs");
        const { chromium } = require("playwright");

        const inputPath = process.argv[2];
        const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));

        function firstExistingFile(path) {
          if (!path || !fs.existsSync(path) || fs.statSync(path).isDirectory()) {
            return null;
          }
          return path;
        }

        async function fillFirst(page, selectors, value) {
          for (const selector of selectors) {
            const locator = page.locator(selector).first();
            if (await locator.count()) {
              await locator.fill(value);
              return selector;
            }
          }
          return null;
        }

        async function clickPublish(page) {
          const labels = /publish|post|submit|save|완료|게시|발행|저장/i;
          const button = page.getByRole("button", { name: labels }).first();
          if (await button.count()) {
            await button.click();
            return "role=button";
          }
          for (const selector of ["button[type=submit]", "input[type=submit]", "[data-action=publish]", "[data-testid=publish]"]) {
            const locator = page.locator(selector).first();
            if (await locator.count()) {
              await locator.click();
              return selector;
            }
          }
          return null;
        }

        (async () => {
          const storageState = firstExistingFile(input.browserSessionRef);
          const browser = await chromium.launch({ headless: true });
          const context = await browser.newContext(storageState ? { storageState } : {});
          const page = await context.newPage();
          await page.goto(input.targetUrl, {
            waitUntil: "domcontentloaded",
            timeout: Math.max(15000, input.maxRuntimeSeconds * 1000)
          });
          await fillFirst(page, [
            "input[name=title]",
            "input[data-field=title]",
            "input[placeholder*=Title i]",
            "input[placeholder*=제목]"
          ], input.objective);
          const filledSelector = await fillFirst(page, [
            "textarea[name=content]",
            "textarea[name=body]",
            "textarea[data-field=content]",
            "textarea",
            "[contenteditable=true]",
            "input[name=content]",
            "input[name=body]"
          ], input.inputSummary);
          const clickedSelector = await clickPublish(page);
          if (clickedSelector) {
            await page.waitForLoadState("domcontentloaded", { timeout: 10000 }).catch(() => {});
            await page.waitForTimeout(500);
          }
          fs.mkdirSync(require("path").dirname(input.screenshotPath), { recursive: true });
          await page.screenshot({ path: input.screenshotPath, fullPage: true });
          const result = {
            targetUrl: input.targetUrl,
            postedUrl: page.url(),
            screenshotPath: input.screenshotPath,
            inputSummary: `${'$'}{input.channel}: ${'$'}{filledSelector || "no editable field"}; ${'$'}{clickedSelector || "no publish button"}`
          };
          await browser.close();
          console.log(JSON.stringify(result));
        })().catch(async (error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
    """.trimIndent()
}

private fun marketingCommandAvailable(command: String): Boolean =
    localCommandAvailable(command)

private const val MARKETING_BROWSER_MAX_RUNTIME_SECONDS = 900
