package com.cotor.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.writeText

@Serializable
data class BrowserSkillCommand(
    val url: String,
    val screenshotPath: String,
    val stepsJson: String? = null,
    val tracePath: String? = null,
    val maxRuntimeSeconds: Int = 60
)

@Serializable
data class BrowserSkillResult(
    val url: String,
    val finalUrl: String,
    val title: String,
    val screenshotPath: String? = null,
    val tracePath: String? = null,
    val consoleErrors: List<String> = emptyList(),
    val actions: List<String> = emptyList()
)

interface BrowserSkillRunner {
    suspend fun execute(command: BrowserSkillCommand): BrowserSkillResult
}

class LocalPlaywrightBrowserSkillRunner(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() },
    private val commandAvailability: (String) -> Boolean = ::browserSkillCommandAvailable
) : BrowserSkillRunner {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    override suspend fun execute(command: BrowserSkillCommand): BrowserSkillResult = withContext(Dispatchers.IO) {
        require(commandAvailability("node") && commandAvailability("npm")) {
            "Browser skill execution requires node and npm so Playwright can run locally."
        }
        val runtimeDir = appHomeProvider()
            .resolve("runtime")
            .resolve("browser-skills")
        val inputDir = runtimeDir.resolve("inputs")
        val scriptPath = runtimeDir.resolve("browser-skill-runner.js")
        runtimeDir.createDirectories()
        inputDir.createDirectories()
        // Install phase runs with its own 120s minimum and must not be capped by the run-phase timeout.
        ensurePlaywrightDependency(runtimeDir, command.maxRuntimeSeconds.coerceAtLeast(15))
        scriptPath.writeText(browserSkillRunnerScript)
        val inputPath = Files.createTempFile(inputDir, "browser-skill-command-", ".json")
        inputPath.writeText(json.encodeToString(BrowserSkillCommand.serializer(), command))
        withTimeout(command.maxRuntimeSeconds.coerceAtLeast(15) * 1_000L) {
            var process: Process? = null
            try {
                process = ProcessBuilder("node", scriptPath.toString(), inputPath.toString())
                    .directory(runtimeDir.toFile())
                    .redirectErrorStream(true)
                    .also { builder ->
                        builder.environment()["NODE_PATH"] = runtimeDir.resolve("node_modules").toString()
                    }
                    .start()
                val timeoutSeconds = command.maxRuntimeSeconds.coerceAtLeast(15).toLong()
                val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)
                val output = process.inputStream.bufferedReader().readText().trim()
                if (!finished) {
                    destroyProcessTree(process)
                    error("Browser skill execution timed out after ${timeoutSeconds}s.")
                }
                if (process.exitValue() != 0) {
                    error(output.ifBlank { "Browser skill execution failed with exit ${process.exitValue()}." })
                }
                runCatching {
                    json.decodeFromString(BrowserSkillResult.serializer(), output.lines().last())
                }.getOrElse { error ->
                    throw IllegalStateException(
                        "Browser skill execution did not return a valid result: ${error.message}. Output: $output"
                    )
                }
            } finally {
                process?.takeIf { it.isAlive }?.let(::destroyProcessTree)
            }
        }
    }

    private fun ensurePlaywrightDependency(runtimeDir: Path, timeoutSeconds: Int) {
        val packageDir = runtimeDir.resolve("node_modules").resolve("playwright")
        if (packageDir.exists()) {
            return
        }
        val process = ProcessBuilder(
            "npm",
            "install",
            "--silent",
            "--no-audit",
            "--no-fund",
            "--prefix",
            runtimeDir.toString(),
            "playwright"
        )
            .redirectErrorStream(true)
            .start()
        val installTimeoutSeconds = timeoutSeconds.coerceAtLeast(120).toLong()
        try {
            val finished = process.waitFor(installTimeoutSeconds, TimeUnit.SECONDS)
            val output = process.inputStream.bufferedReader().readText().trim()
            if (!finished) {
                destroyProcessTree(process)
                error("Playwright dependency install timed out after ${installTimeoutSeconds}s.")
            }
            if (process.exitValue() != 0) {
                error(output.ifBlank { "Playwright dependency install failed with exit ${process.exitValue()}." })
            }
        } finally {
            process.takeIf { it.isAlive }?.let(::destroyProcessTree)
        }
    }

    private val browserSkillRunnerScript: String = """
        const fs = require("fs");
        const path = require("path");
        const { chromium } = require("playwright");

        const input = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
        const allowedTypes = new Set(["goto", "click", "fill", "press", "assertText", "screenshot"]);

        function parseSteps(raw) {
          if (!raw || !String(raw).trim()) return [];
          const parsed = JSON.parse(raw);
          if (!Array.isArray(parsed)) throw new Error("stepsJson must be a JSON array.");
          return parsed.map((step, index) => {
            const type = String(step.type || "").trim();
            if (!allowedTypes.has(type)) {
              throw new Error(`Unsupported browser skill step at ${'$'}{index}: ${'$'}{type}`);
            }
            return { ...step, type };
          });
        }

        async function runStep(page, step, actions) {
          switch (step.type) {
            case "goto":
              await page.goto(step.url, { waitUntil: "domcontentloaded", timeout: 30000 });
              actions.push(`goto ${'$'}{step.url}`);
              break;
            case "click":
              await page.locator(step.selector).first().click({ timeout: 15000 });
              actions.push(`click ${'$'}{step.selector}`);
              break;
            case "fill":
              await page.locator(step.selector).first().fill(String(step.value || ""), { timeout: 15000 });
              actions.push(`fill ${'$'}{step.selector}`);
              break;
            case "press":
              await page.keyboard.press(String(step.key || "Enter"));
              actions.push(`press ${'$'}{step.key || "Enter"}`);
              break;
            case "assertText": {
              const text = await page.locator("body").innerText({ timeout: 15000 });
              if (!text.includes(String(step.text || ""))) {
                throw new Error(`Expected text not found: ${'$'}{step.text || ""}`);
              }
              actions.push(`assertText ${'$'}{step.text || ""}`);
              break;
            }
            case "screenshot":
              fs.mkdirSync(path.dirname(step.path || input.screenshotPath), { recursive: true });
              await page.screenshot({ path: step.path || input.screenshotPath, fullPage: true });
              actions.push(`screenshot ${'$'}{step.path || input.screenshotPath}`);
              break;
          }
        }

        (async () => {
          const steps = parseSteps(input.stepsJson);
          const actions = [];
          const consoleErrors = [];
          const browser = await chromium.launch({ headless: true });
          const context = await browser.newContext();
          if (input.tracePath) {
            await context.tracing.start({ screenshots: true, snapshots: true });
          }
          const page = await context.newPage();
          page.on("console", (msg) => {
            if (msg.type() === "error") consoleErrors.push(msg.text());
          });
          page.on("pageerror", (error) => consoleErrors.push(error && error.message ? error.message : String(error)));
          await page.goto(input.url, { waitUntil: "domcontentloaded", timeout: Math.max(15000, input.maxRuntimeSeconds * 1000) });
          actions.push(`goto ${'$'}{input.url}`);
          for (const step of steps) {
            await runStep(page, step, actions);
          }
          await page.waitForLoadState("domcontentloaded", { timeout: 5000 }).catch(() => {});
          fs.mkdirSync(path.dirname(input.screenshotPath), { recursive: true });
          await page.screenshot({ path: input.screenshotPath, fullPage: true });
          if (input.tracePath) {
            fs.mkdirSync(path.dirname(input.tracePath), { recursive: true });
            await context.tracing.stop({ path: input.tracePath });
          }
          const result = {
            url: input.url,
            finalUrl: page.url(),
            title: await page.title(),
            screenshotPath: input.screenshotPath,
            tracePath: input.tracePath || null,
            consoleErrors,
            actions
          };
          await browser.close();
          console.log(JSON.stringify(result));
        })().catch(async (error) => {
          console.error(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
    """.trimIndent()
}

private fun browserSkillCommandAvailable(command: String): Boolean =
    runCatching {
        val process = ProcessBuilder(command, "--version")
            .redirectErrorStream(true)
            .start()
        try {
            process.waitFor(5, TimeUnit.SECONDS) && process.exitValue() == 0
        } finally {
            process.takeIf { it.isAlive }?.let(::destroyProcessTree)
        }
    }.getOrDefault(false)
