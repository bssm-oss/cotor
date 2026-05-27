package com.cotor.app

import com.cotor.storage.writeTextAtomically
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.deleteIfExists
import kotlin.io.path.exists

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
    suspend fun prewarm() {}
}

class LocalPlaywrightBrowserSkillRunner internal constructor(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() },
    private val commandAvailability: (String) -> Boolean = ::browserSkillCommandAvailable,
    private val processRunner: LocalSkillProcessRunner = defaultLocalSkillProcessRunner
) : BrowserSkillRunner {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    override suspend fun execute(command: BrowserSkillCommand): BrowserSkillResult = withContext(Dispatchers.IO) {
        val runtimeRoot = appHomeProvider()
            .toAbsolutePath()
            .normalize()
            .resolve("runtime")
        val screenshotPath = requireLocalBrowserRuntimeOutputPath(
            rawPath = command.screenshotPath,
            runtimeRoot = runtimeRoot,
            label = "screenshotPath"
        )
        val tracePath = command.tracePath?.let {
            requireLocalBrowserRuntimeOutputPath(
                rawPath = it,
                runtimeRoot = runtimeRoot,
                label = "tracePath"
            )
        }
        val normalizedCommand = command.copy(
            screenshotPath = screenshotPath.toString(),
            stepsJson = sanitizeBrowserSkillStepsJson(
                stepsJson = command.stepsJson,
                screenshotPath = screenshotPath.toString(),
                runtimeRoot = runtimeRoot,
                json = json
            ),
            tracePath = tracePath?.toString(),
            maxRuntimeSeconds = normalizeLocalBrowserRuntimeSeconds(
                command.maxRuntimeSeconds,
                BROWSER_SKILL_MAX_RUNTIME_SECONDS
            )
        )
        require(commandAvailability("node") && commandAvailability("npm")) {
            "Browser skill execution requires node and npm so Playwright can run locally."
        }
        val runtimeDir = runtimeRoot
            .resolve("browser-skills")
        val inputDir = runtimeDir.resolve("inputs")
        val scriptPath = runtimeDir.resolve("browser-skill-runner.js")
        runtimeDir.createDirectories()
        inputDir.createDirectories()
        // Install phase runs with its own 120s minimum and must not be capped by the run-phase timeout.
        ensurePlaywrightDependency(runtimeDir, normalizedCommand.maxRuntimeSeconds)
        writeTextAtomically(scriptPath, browserSkillRunnerScript)
        val inputPath = Files.createTempFile(inputDir, "browser-skill-command-", ".json")
        try {
            writeTextAtomically(inputPath, json.encodeToString(BrowserSkillCommand.serializer(), normalizedCommand))
            val timeoutSeconds = normalizedCommand.maxRuntimeSeconds.toLong()
            val result = processRunner.run(
                command = listOf("node", scriptPath.toString(), inputPath.toString()),
                workingDirectory = runtimeDir,
                timeoutSeconds = timeoutSeconds,
                timeoutMessage = "Browser skill execution timed out after ${timeoutSeconds}s.",
                environment = mapOf("NODE_PATH" to runtimeDir.resolve("node_modules").toString())
            )
            val output = result.output.trim()
            if (result.exitCode != 0) {
                error(output.ifBlank { "Browser skill execution failed with exit ${result.exitCode}." })
            }
            runCatching {
                json.decodeFromString(BrowserSkillResult.serializer(), output.lines().last())
            }.getOrElse { error ->
                throw IllegalStateException(
                    "Browser skill execution did not return a valid result: ${error.message}. Output: $output"
                )
            }
        } finally {
            inputPath.deleteIfExists()
        }
    }

    override suspend fun prewarm(): Unit = withContext(Dispatchers.IO) {
        if (commandAvailability("node") && commandAvailability("npm")) {
            val runtimeDir = appHomeProvider()
                .resolve("runtime")
                .resolve("browser-skills")
            runtimeDir.createDirectories()
            ensurePlaywrightDependency(runtimeDir, 60)
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
              fs.mkdirSync(path.dirname(input.screenshotPath), { recursive: true });
              await page.screenshot({ path: input.screenshotPath, fullPage: true });
              actions.push(`screenshot ${'$'}{input.screenshotPath}`);
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
    localCommandAvailable(command)

internal fun normalizeLocalBrowserRuntimeSeconds(requestedSeconds: Int, maxSeconds: Int): Int =
    requestedSeconds.coerceIn(LOCAL_BROWSER_MIN_RUNTIME_SECONDS, maxSeconds.coerceAtLeast(LOCAL_BROWSER_MIN_RUNTIME_SECONDS))

internal fun requireLocalBrowserRuntimeOutputPath(rawPath: String, runtimeRoot: Path, label: String): Path {
    val normalizedRoot = runtimeRoot.toAbsolutePath().normalize()
    val normalizedPath = Path.of(rawPath).toAbsolutePath().normalize()
    require(normalizedPath.startsWith(normalizedRoot)) {
        "$label must stay under Cotor runtime directory: $normalizedRoot"
    }
    return normalizedPath
}

internal fun sanitizeBrowserSkillStepsJson(
    stepsJson: String?,
    screenshotPath: String,
    runtimeRoot: Path,
    json: Json = Json { ignoreUnknownKeys = true }
): String? {
    val raw = stepsJson?.trim()?.takeIf { it.isNotBlank() } ?: return null
    val parsed = json.parseToJsonElement(raw)
    require(parsed is JsonArray) { "stepsJson must be a JSON array." }
    val sanitizedSteps = parsed.mapIndexed { index, step ->
        require(step is JsonObject) { "stepsJson[$index] must be a JSON object." }
        val type = step["type"]?.jsonPrimitive?.contentOrNull?.trim()
        if (type != "screenshot") {
            step
        } else {
            step["path"]?.jsonPrimitive?.contentOrNull
                ?.trim()
                ?.takeIf { it.isNotBlank() }
                ?.let {
                    requireLocalBrowserRuntimeOutputPath(
                        rawPath = it,
                        runtimeRoot = runtimeRoot,
                        label = "stepsJson[$index].path"
                    )
                }
            JsonObject(step + ("path" to JsonPrimitive(screenshotPath)))
        }
    }
    return JsonArray(sanitizedSteps).toString()
}

private const val LOCAL_BROWSER_MIN_RUNTIME_SECONDS = 15
private const val BROWSER_SKILL_MAX_RUNTIME_SECONDS = 300
