package com.cotor.data.plugin

/**
 * File overview for ClaudePlugin.
 *
 * This file belongs to the plugin integration layer that adapts external agent CLIs into Cotor.
 * It groups declarations around a i model plugins so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.data.http.CotorHttpClients
import com.cotor.data.process.ProcessManager
import com.cotor.model.*
import com.cotor.model.OpenCodeDefaults
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.URI
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.time.Duration
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Claude AI Plugin (Anthropic)
 * Executes: claude --dangerously-skip-permissions --print <prompt>
 */
class ClaudePlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "claude",
        version = "1.0.0",
        description = "Claude AI by Anthropic for code generation and analysis",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.JSON, DataFormat.TEXT)
    )

    override val parameterSchema = AgentParameterSchema(
        parameters = listOf(
            AgentParameter(
                name = "model",
                type = ParameterType.STRING,
                required = false,
                description = "The Claude model to use.",
                defaultValue = "claude-sonnet-4-20250514"
            ),
            AgentParameter(
                name = "temperature",
                type = ParameterType.NUMBER,
                required = false,
                description = "The temperature to use for the model.",
                defaultValue = "0.7"
            )
        )
    )

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")

        val model = context.parameters.getOrDefault("model", "claude-sonnet-4-20250514")

        // Execute Claude CLI with auto-approval (skip all permission prompts)
        // NOTE: `claude` CLI does not consistently support `--temperature` across versions,
        // so we avoid passing it here for compatibility.
        val command = mutableListOf("claude", "--dangerously-skip-permissions", "--print", prompt)
        if (model.isNotBlank()) {
            command.add("--model")
            command.add(model)
        }

        val result = processManager.executeProcess(
            command = command,
            input = null,
            environment = context.environment,
            timeout = context.timeout,
            workingDirectory = context.workingDirectory,
            onStart = context.onProcessStarted,
            onStdoutChunk = context.onStdoutChunk
        )

        if (!result.isSuccess) {
            throw AgentExecutionException("Claude execution failed: ${result.stderr}")
        }

        return PluginExecutionOutput(result.stdout, result.processId)
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for Claude"))
        }
        return ValidationResult.Success
    }
}

/**
 * Codex Plugin (OpenAI Code Interpreter)
 * Executes: codex --dangerously-bypass-approvals-and-sandbox <prompt>
 */
class CodexPlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "codex",
        version = "1.0.0",
        description = "Codex AI for code generation",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.JSON, DataFormat.TEXT)
    )

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")
        val authMode = context.parameters["auth_mode"]?.trim()?.lowercase()
        val baseEnvironment = if (authMode == "oauth") {
            context.environment + mapOf("CODEX_HOME" to effectiveCodexOAuthHome(context.environment).toString())
        } else {
            context.environment
        }
        val reasoningEffort = normalizeCodexReasoningEffort(
            context.parameters["model_reasoning_effort"] ?: context.parameters["reasoning_effort"]
        )
        val model = CodexDefaults.normalizeModel(
            context.parameters["model"]?.trim()?.takeIf { it.isNotEmpty() }
                ?: resolveConfiguredCodexModel(baseEnvironment)
        )
        val isolateCodexHome = shouldIsolateCodexMcpConfig(context) && authMode != "oauth"

        // Codex writes its last assistant message to a file more reliably than stdout
        // when the CLI emits extra progress/logging lines, so we preserve that path.
        val outputFile = kotlin.io.path.createTempFile("cotor-codex-", ".txt")
        val isolatedCodexHome = if (isolateCodexHome) {
            kotlin.io.path.createTempDirectory("cotor-codex-home-").also {
                prepareIsolatedCodexHome(it, baseEnvironment)
            }
        } else {
            null
        }

        try {
            // Execute Codex in non-interactive mode and write only the final assistant message to file.
            val command = mutableListOf(
                "codex", "exec",
                "--skip-git-repo-check",
                "--full-auto",
                "--color", "never",
                "-c", """model_reasoning_effort="$reasoningEffort"""",
                "--output-last-message", outputFile.toString()
            )
            if (isolateCodexHome) {
                // Company/runtime task execution should not inherit flaky or expired MCP login state
                // from the user's interactive Codex setup.
                command += listOf("-c", "mcp_servers={}")
            }
            if (model != null) {
                command += listOf("--model", model)
            }
            command += prompt

            val result = processManager.executeProcess(
                command = command,
                input = null,
                environment = if (isolatedCodexHome != null) {
                    baseEnvironment + mapOf("CODEX_HOME" to isolatedCodexHome.toString())
                } else {
                    baseEnvironment
                },
                timeout = context.timeout,
                workingDirectory = context.workingDirectory,
                onStart = context.onProcessStarted
            )

            // Prefer the captured final assistant message and fall back to stdout only when
            // the file is empty, which keeps the plugin resilient across CLI versions.
            val finalText = Files.readString(outputFile).trim()

            if (!result.isSuccess && finalText.isBlank()) {
                throw AgentExecutionException("Codex execution failed: ${result.stderr.ifBlank { result.stdout }}")
            }

            return PluginExecutionOutput(
                output = if (finalText.isNotBlank()) finalText else result.stdout,
                processId = result.processId
            )
        } finally {
            runCatching {
                withTimeoutOrNull(2_000) {
                    withContext(Dispatchers.IO) {
                        Files.deleteIfExists(outputFile)
                        isolatedCodexHome?.let { cleanupCodexHome(it) }
                    }
                }
            }
        }
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for Codex"))
        }
        return ValidationResult.Success
    }

    private fun normalizeCodexReasoningEffort(raw: String?): String =
        when (raw?.trim()?.lowercase()) {
            "none", "minimal", "low", "medium", "high" -> raw.trim().lowercase()
            "xhigh" -> "high"
            else -> "high"
        }

    private fun prepareIsolatedCodexHome(targetHome: Path, environment: Map<String, String>) {
        Files.createDirectories(targetHome)
        resolveCodexAuthSource(environment)
            ?.takeIf { Files.exists(it) }
            ?.let { source ->
                Files.copy(source, targetHome.resolve("auth.json"), StandardCopyOption.REPLACE_EXISTING)
            }
        Files.writeString(targetHome.resolve("config.toml"), buildIsolatedCodexConfig())
    }

    private fun resolveConfiguredCodexModel(environment: Map<String, String>): String? {
        val configPath = resolveCodexConfigPath(environment) ?: return null
        if (!Files.exists(configPath)) return null
        return CodexDefaults.normalizeModel(
            Files.readAllLines(configPath)
                .firstOrNull { line ->
                    val trimmed = line.trim()
                    trimmed.startsWith("model = ") && !trimmed.startsWith("model_reasoning_effort")
                }
                ?.substringAfter("=")
                ?.trim()
                ?.removeSurrounding("\"")
                ?.takeIf { it.isNotBlank() }
        )
    }

    private fun resolveCodexAuthSource(environment: Map<String, String>): Path? =
        resolveCodexHome(environment)?.resolve("auth.json")

    private fun resolveCodexConfigPath(environment: Map<String, String>): Path? =
        resolveCodexHome(environment)?.resolve("config.toml")

    private fun resolveCodexHome(environment: Map<String, String>): Path? {
        val explicitCodexHome = environment["CODEX_HOME"]
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("CODEX_HOME")?.takeIf { it.isNotBlank() }
        if (explicitCodexHome != null) {
            return Path.of(explicitCodexHome)
        }
        val home = environment["HOME"]
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("HOME")?.takeIf { it.isNotBlank() }
            ?: System.getProperty("user.home")?.takeIf { it.isNotBlank() }
        return home?.let { Path.of(it).resolve(".codex") }
    }

    private fun managedCodexOAuthHome(environment: Map<String, String>): Path {
        val explicit = environment["COTOR_CODEX_OAUTH_HOME"]?.trim()?.takeIf { it.isNotBlank() }
        if (explicit != null) {
            return Path.of(explicit)
        }
        val home = environment["HOME"]
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: System.getProperty("user.home")
        return Path.of(home).resolve(".cotor").resolve("auth").resolve("codex-oauth")
    }

    private fun effectiveCodexOAuthHome(environment: Map<String, String>): Path {
        val managed = managedCodexOAuthHome(environment)
        val native = resolveCodexHome(environment)
        val managedAuth = managed.resolve("auth.json")
        val nativeAuth = native?.resolve("auth.json")

        return when {
            nativeAuth != null && Files.exists(nativeAuth) && Files.exists(managedAuth) -> {
                val managedUpdatedAt = Files.getLastModifiedTime(managedAuth).toMillis()
                val nativeUpdatedAt = Files.getLastModifiedTime(nativeAuth).toMillis()
                if (nativeUpdatedAt > managedUpdatedAt) native else managed
            }
            nativeAuth != null && Files.exists(nativeAuth) -> native
            else -> managed
        }
    }

    private fun buildIsolatedCodexConfig(): String = """
        [features]
        rmcp_client = false
        multi_agent = false
        js_repl = false
        apps = false
        prevent_idle_sleep = false
    """.trimIndent() + "\n"

    private fun shouldIsolateCodexMcpConfig(context: ExecutionContext): Boolean =
        !context.taskId.isNullOrBlank()

    private fun cleanupCodexHome(path: Path) {
        if (!Files.exists(path)) return
        Files.walk(path)
            .sorted(Comparator.reverseOrder())
            .forEach { candidate ->
                runCatching { Files.deleteIfExists(candidate) }
            }
    }
}

/**
 * GitHub Copilot Plugin
 * Executes: copilot -p <prompt> --allow-all-tools
 * Note: Copilot doesn't support full auto-approval, uses session-based silent auth
 */
class CopilotPlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "copilot",
        version = "1.0.0",
        description = "GitHub Copilot for code suggestions",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.TEXT)
    )

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")

        // Copilot's session model is quieter than the other CLIs, so this wrapper simply
        // forwards the prompt and trusts the pre-authenticated CLI state on the machine.
        // Note: Full auto-approval not supported, requires pre-authenticated session
        val command = listOf("copilot", "-p", prompt, "--allow-all-tools")

        val result = processManager.executeProcess(
            command = command,
            input = null,
            environment = context.environment,
            timeout = context.timeout,
            workingDirectory = context.workingDirectory,
            onStart = context.onProcessStarted
        )

        if (!result.isSuccess) {
            throw AgentExecutionException("GitHub Copilot execution failed: ${result.stderr}")
        }

        return PluginExecutionOutput(result.stdout, result.processId)
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for Copilot"))
        }
        return ValidationResult.Success
    }
}

/**
 * Google Gemini Plugin
 * Executes: gemini --yolo <prompt>
 * Uses alwaysAllow whitelist for auto-approval
 */
class GeminiPlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "gemini",
        version = "1.0.0",
        description = "Google Gemini for code generation and analysis",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.JSON, DataFormat.TEXT)
    )

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")

        // Gemini exposes a single flag for broad tool approval, so the wrapper remains
        // intentionally thin and lets cwd/env carry the worktree isolation.
        // --yolo flag enables alwaysAllow mode for all tools
        val command = listOf("gemini", "--yolo", prompt)

        val result = processManager.executeProcess(
            command = command,
            input = null,
            environment = context.environment,
            timeout = context.timeout,
            workingDirectory = context.workingDirectory,
            onStart = context.onProcessStarted
        )

        if (!result.isSuccess) {
            throw AgentExecutionException("Gemini execution failed: ${result.stderr}")
        }

        return PluginExecutionOutput(result.stdout, result.processId)
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for Gemini"))
        }
        return ValidationResult.Success
    }
}

/**
 * Cursor AI Plugin
 * Executes: cursor-cli generate --auto-run <prompt>
 * Uses Auto-Run mode with Denylist for dangerous commands
 */
class CursorPlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "cursor",
        version = "1.0.0",
        description = "Cursor AI for intelligent code editing",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.TEXT)
    )

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")

        // Cursor's CLI is another child-process-based integration, so its output path
        // mirrors the other local tools and captures the pid for port inspection.
        // Uses Denylist approach: auto-runs everything except dangerous commands (rm, etc)
        val command = listOf("cursor-cli", "generate", "--auto-run", prompt)

        val result = processManager.executeProcess(
            command = command,
            input = null,
            environment = context.environment,
            timeout = context.timeout,
            workingDirectory = context.workingDirectory,
            onStart = context.onProcessStarted
        )

        if (!result.isSuccess) {
            throw AgentExecutionException("Cursor execution failed: ${result.stderr}")
        }

        return PluginExecutionOutput(result.stdout, result.processId)
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for Cursor"))
        }
        return ValidationResult.Success
    }
}

/**
 * Local model plugin for Ollama and LM Studio/OpenAI-compatible servers.
 */
class LocalModelPlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "local-model",
        version = "1.0.0",
        description = "Local Gemma/Ollama/LM Studio model connection",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.JSON, DataFormat.TEXT)
    )

    override val parameterSchema = AgentParameterSchema(
        parameters = listOf(
            AgentParameter(
                name = "provider",
                type = ParameterType.STRING,
                required = false,
                description = "Local model provider: ollama or lmstudio.",
                defaultValue = "ollama"
            ),
            AgentParameter(
                name = "baseUrl",
                type = ParameterType.STRING,
                required = false,
                description = "Provider base URL.",
                defaultValue = LocalModelDefaults.OLLAMA_BASE_URL
            ),
            AgentParameter(
                name = "model",
                type = ParameterType.STRING,
                required = false,
                description = "Local model name.",
                defaultValue = LocalModelDefaults.GEMMA4_MODEL
            )
        )
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val client = CotorHttpClients.newClient()

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required for local model")
        val provider = normalizeProvider(context.parameters["provider"] ?: context.agentName)
        val model = LocalModelDefaults.normalizeModel(context.parameters["model"]) ?: LocalModelDefaults.GEMMA4_MODEL
        val baseUrl = when (provider) {
            "lmstudio" -> LocalModelDefaults.normalizeBaseUrl(context.parameters["baseUrl"], LocalModelDefaults.LM_STUDIO_BASE_URL)
            else -> LocalModelDefaults.normalizeBaseUrl(context.parameters["baseUrl"], LocalModelDefaults.OLLAMA_BASE_URL)
        }
        return when (provider) {
            "lmstudio" -> executeLmStudio(baseUrl, model, prompt, context.timeout)
            else -> executeOllama(baseUrl, model, prompt, context.timeout)
        }
    }

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for local model"))
        }
        return ValidationResult.Success
    }

    private fun normalizeProvider(raw: String): String =
        when (raw.trim().lowercase()) {
            "lmstudio", "lm-studio", "lm_studio", "lm studio" -> "lmstudio"
            else -> "ollama"
        }

    private fun executeOllama(baseUrl: String, model: String, prompt: String, timeoutMs: Long): PluginExecutionOutput {
        ensureManagedOllamaServer(baseUrl)
        val response = runCatching {
            postJson("$baseUrl/api/chat", ollamaChatBody(model, prompt), timeoutMs)
        }.recoverCatching { error ->
            val fallbackModel = ollamaFallbackModel(baseUrl, requestedModel = model)
            if (fallbackModel != null && isModelNotFound(error)) {
                postJson("$baseUrl/api/chat", ollamaChatBody(fallbackModel, prompt), timeoutMs)
            } else {
                throw error
            }
        }.getOrThrow()
        return PluginExecutionOutput(extractOllamaText(response.body()))
    }

    private fun ollamaChatBody(model: String, prompt: String): String =
        buildJsonObject {
            put("model", model)
            put("stream", false)
            put(
                "messages",
                buildJsonArray {
                    addMessage("user", prompt)
                }
            )
        }.toString()

    private fun extractOllamaText(body: String): String {
        val parsed = json.parseToJsonElement(body).jsonObject
        return parsed["message"]?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull
            ?: parsed["response"]?.jsonPrimitive?.contentOrNull
            ?: body
    }

    private fun ollamaFallbackModel(baseUrl: String, requestedModel: String): String? {
        val requested = LocalModelDefaults.normalizeModel(requestedModel) ?: return null
        if (!LocalModelDefaults.isGemmaFamilyModel(requested)) return null
        val models = getOllamaModels(baseUrl)
        return LocalModelDefaults.preferredInstalledGemmaModels(models)
            .firstOrNull { !it.equals(requested, ignoreCase = true) }
    }

    private fun getOllamaModels(baseUrl: String): List<String> =
        runCatching {
            val response = getJson("$baseUrl/api/tags", timeoutMs = 2_000)
            json.parseToJsonElement(response.body()).jsonObject["models"]?.jsonArray
                ?.mapNotNull { model ->
                    val obj = model.jsonObject
                    val remoteHost = obj["remote_host"]?.jsonPrimitive?.contentOrNull
                    val name = obj["name"]?.jsonPrimitive?.contentOrNull
                        ?: obj["model"]?.jsonPrimitive?.contentOrNull
                    name.takeIf { LocalModelDefaults.isLocalOllamaTag(it, remoteHost) }
                }
                ?.mapNotNull(LocalModelDefaults::normalizeModel)
                ?.distinct()
                ?: emptyList()
        }.getOrDefault(emptyList())

    private fun executeLmStudio(baseUrl: String, model: String, prompt: String, timeoutMs: Long): PluginExecutionOutput {
        val body = buildJsonObject {
            put("model", model)
            put("stream", false)
            put(
                "messages",
                buildJsonArray {
                    addMessage("user", prompt)
                }
            )
        }.toString()
        val response = postJson("$baseUrl/chat/completions", body, timeoutMs)
        val parsed = json.parseToJsonElement(response.body()).jsonObject
        val text = parsed["choices"]?.jsonArray?.firstOrNull()
            ?.jsonObject?.get("message")?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull
            ?: response.body()
        return PluginExecutionOutput(text)
    }

    private fun postJson(url: String, body: String, timeoutMs: Long): HttpResponse<String> {
        val request = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofMillis(timeoutMs.coerceAtLeast(1_000L)))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build()
        val response = client.send(request, HttpResponse.BodyHandlers.ofString())
        if (response.statusCode() !in 200..299) {
            throw AgentExecutionException("Local model request failed (${response.statusCode()}): ${response.body()}")
        }
        return response
    }

    private fun getJson(url: String, timeoutMs: Long): HttpResponse<String> {
        val request = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofMillis(timeoutMs.coerceAtLeast(1_000L)))
            .GET()
            .build()
        val response = client.send(request, HttpResponse.BodyHandlers.ofString())
        if (response.statusCode() !in 200..299) {
            throw AgentExecutionException("Local model request failed (${response.statusCode()}): ${response.body()}")
        }
        return response
    }

    private fun isModelNotFound(error: Throwable): Boolean {
        val message = error.message.orEmpty()
        return message.contains("not found", ignoreCase = true) &&
            message.contains("model", ignoreCase = true)
    }

    private fun ensureManagedOllamaServer(baseUrl: String) {
        if (!isDefaultLoopbackOllamaBaseUrl(baseUrl)) return
        if (runCatching { getJson("$baseUrl/api/tags", timeoutMs = 1_000) }.isSuccess) return
        val executable = resolveOllamaExecutable() ?: return
        synchronized(ollamaServerLock) {
            if (managedOllamaProcess?.isAlive == true) return@synchronized
            managedOllamaProcess = ProcessBuilder(executable, "serve")
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .apply {
                    environment()["OLLAMA_HOST"] = "127.0.0.1:11434"
                }
                .start()
        }
        val deadline = System.currentTimeMillis() + 5_000L
        while (System.currentTimeMillis() < deadline) {
            if (runCatching { getJson("$baseUrl/api/tags", timeoutMs = 1_000) }.isSuccess) return
            Thread.sleep(100)
        }
    }

    private fun isDefaultLoopbackOllamaBaseUrl(baseUrl: String): Boolean {
        val uri = runCatching { URI.create(baseUrl) }.getOrNull() ?: return false
        val host = uri.host ?: return false
        val port = if (uri.port == -1) 80 else uri.port
        return uri.scheme.equals("http", ignoreCase = true) &&
            port == 11434 &&
            host in setOf("127.0.0.1", "localhost", "::1")
    }

    private fun resolveOllamaExecutable(): String? {
        val pathCandidates = System.getenv("PATH")
            .orEmpty()
            .split(java.io.File.pathSeparator)
            .filter { it.isNotBlank() }
            .map { Path.of(it).resolve("ollama") }
        val candidates = pathCandidates + listOf(
            Path.of("/opt/homebrew/bin/ollama"),
            Path.of("/usr/local/bin/ollama"),
            Path.of("/usr/bin/ollama")
        )
        return candidates.firstOrNull { Files.isExecutable(it) }?.toString()
    }

    private fun kotlinx.serialization.json.JsonArrayBuilder.addMessage(role: String, content: String) {
        add(
            buildJsonObject {
                put("role", role)
                put("content", content)
            }
        )
    }

    companion object {
        private val ollamaServerLock = Any()

        @Volatile
        private var managedOllamaProcess: Process? = null
    }
}

/**
 * OpenCode Agent Plugin
 * Executes: opencode run --format json --file <prompt-file> <instruction>
 * Default permission: "allow" for all methods (configured in opencode.json)
 */
class OpenCodePlugin : AgentPlugin {
    override val metadata = AgentMetadata(
        name = "opencode",
        version = "1.0.0",
        description = "OpenCode agent for open-source code generation",
        author = "Cotor Team",
        supportedFormats = listOf(DataFormat.JSON, DataFormat.TEXT)
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val httpClient = CotorHttpClients.newClient()

    override suspend fun execute(
        context: ExecutionContext,
        processManager: ProcessManager
    ): PluginExecutionOutput {
        val prompt = context.input ?: throw IllegalArgumentException("Input prompt is required")
        val requestedModel = OpenCodeDefaults.normalizeModel(
            context.parameters["model"] ?: context.environment["OPENCODE_MODEL"]
        )
        val executionContext = if (OpenCodeDefaults.isLocalOllamaModel(requestedModel)) {
            context.copy(environment = OpenCodeDefaults.localOllamaEnvironment(context.environment))
        } else {
            context
        }
        requestedModel
            ?.takeIf(OpenCodeDefaults::isLocalOllamaModel)
            ?.let { ensureLocalOllamaModelAvailable(it, executionContext) }

        var model = requestedModel
        if (requestedModel != null) {
            model = resolvePreferredOpenCodeModel(
                processManager = processManager,
                context = executionContext,
                requestedModel = requestedModel
            )
        }
        var result = executeOpenCodeRun(
            prompt = prompt,
            model = model,
            context = executionContext,
            processManager = processManager
        )
        val initialError = extractOpenCodeError(result)

        if (
            requestedModel != null &&
            (
                initialError?.contains("Model not found", ignoreCase = true) == true ||
                    initialError?.let(::isOpenCodeProviderRateLimit) == true
                )
        ) {
            val fallbackModel = discoverFallbackOpenCodeModel(
                processManager = processManager,
                context = executionContext,
                rejectedModel = requestedModel
            )
            if (fallbackModel != null) {
                model = fallbackModel
                result = executeOpenCodeRun(
                    prompt = prompt,
                    model = model,
                    context = executionContext,
                    processManager = processManager
                )
            }
        }

        val parsedText = parseOpenCodeJsonOutput(result.stdout)
        val finalError = extractOpenCodeError(result)
            ?.let { normalizeLocalOllamaExecutionError(it, requestedModel) }
        if (parsedText.isNotBlank() && finalError?.let(::isOpenCodePostTextSerializationError) == true) {
            return PluginExecutionOutput(parsedText, result.processId)
        }
        if (!result.isSuccess || finalError != null) {
            throw ProcessExecutionException(
                message = "OpenCode execution failed",
                exitCode = result.exitCode,
                stdout = result.stdout.ifBlank { finalError ?: result.stdout },
                stderr = result.stderr.ifBlank { finalError ?: result.stderr }
            )
        }
        if (result.stdout.isBlank()) {
            throw ProcessExecutionException(
                message = "OpenCode execution failed",
                exitCode = result.exitCode,
                stdout = "opencode run exit 0 but stdout and stderr were both empty",
                stderr = "opencode run exit 0 but stdout and stderr were both empty"
            )
        }
        if (parsedText.isBlank() && containsStructuredOpenCodeEvents(result.stdout)) {
            throw ProcessExecutionException(
                message = "OpenCode execution failed",
                exitCode = result.exitCode,
                stdout = result.stdout,
                stderr = "opencode run completed without assistant text"
            )
        }

        return PluginExecutionOutput(parsedText, result.processId)
    }

    private suspend fun executeOpenCodeRun(
        prompt: String,
        model: String?,
        context: ExecutionContext,
        processManager: ProcessManager
    ): ProcessResult {
        // OpenCode run with --format json produces a structured JSON event stream
        // instead of launching an interactive TUI. Events include step_start, text,
        // step_finish, etc. We parse text events to extract the response content.
        // Default permission is "allow" for all methods (configured via opencode yolo mode).
        // Keep the full task prompt out of process arguments; it may contain repo
        // context or user text that should not be visible via `ps`.
        val promptFile = withContext(Dispatchers.IO) {
            val promptDir = context.workingDirectory
                ?.resolve(".cotor/runtime/opencode-prompts")
                ?.also { Files.createDirectories(it) }
                ?: Path.of(System.getProperty("java.io.tmpdir"))
            Files.createTempFile(promptDir, "opencode-prompt-", ".md").also { path ->
                runCatching {
                    Files.setPosixFilePermissions(
                        path,
                        java.nio.file.attribute.PosixFilePermissions.fromString("rw-------")
                    )
                }
                Files.writeString(path, prompt)
            }
        }
        val ephemeralConfig = withContext(Dispatchers.IO) {
            createEphemeralOpenCodeConfig(context)
        }
        val fatalRuntimeError = AtomicReference<String?>(null)
        val childProcessId = AtomicLong(-1L)
        val command = buildList {
            add("opencode")
            add("run")
            add("--print-logs")
            add("--log-level")
            add("ERROR")
            context.parameters["agent"]
                ?.trim()
                ?.takeIf { it.isNotBlank() }
                ?.let {
                    add("--agent")
                    add(it)
                }
            model?.let {
                add("--model")
                add(it)
            }
            add("--format")
            add("json")
            add("Execute the instructions in the attached prompt file.")
            add("--file=$promptFile")
        }

        return try {
            val result = coroutineScope {
                val killer = launch(Dispatchers.IO) {
                    while (isActive && fatalRuntimeError.get() == null) {
                        delay(100)
                    }
                    if (fatalRuntimeError.get() != null) {
                        repeat(20) {
                            val pid = childProcessId.get()
                            if (pid > 0) {
                                ProcessHandle.of(pid).ifPresent { handle ->
                                    handle.destroyForcibly()
                                }
                                return@launch
                            }
                            delay(50)
                        }
                    }
                }
                try {
                    processManager.executeProcess(
                        command = command,
                        input = null,
                        environment = context.environment,
                        timeout = context.timeout,
                        workingDirectory = context.workingDirectory,
                        onStart = { pid ->
                            childProcessId.set(pid)
                            context.onProcessStarted?.invoke(pid)
                        },
                        onStdoutChunk = context.onStdoutChunk,
                        onStderrChunk = { chunk ->
                            classifyFatalOpenCodeRuntimeLog(chunk)?.let { reason ->
                                fatalRuntimeError.compareAndSet(null, reason)
                            }
                        }
                    )
                } finally {
                    killer.cancel()
                }
            }
            fatalRuntimeError.get()?.let { reason ->
                return result.copy(
                    exitCode = if (result.exitCode == 0) 143 else result.exitCode,
                    stderr = listOf(result.stderr, reason).filter { it.isNotBlank() }.joinToString("\n"),
                    isSuccess = false
                )
            }
            result
        } finally {
            withContext(Dispatchers.IO) {
                runCatching { Files.deleteIfExists(promptFile) }
                restoreEphemeralOpenCodeConfig(ephemeralConfig)
            }
        }
    }

    private data class EphemeralOpenCodeConfig(
        val configPath: Path,
        val backupPath: Path?
    )

    private fun createEphemeralOpenCodeConfig(context: ExecutionContext): EphemeralOpenCodeConfig? {
        val configJson = ephemeralOpenCodeConfigJson(context) ?: return null
        val workdir = context.workingDirectory ?: return null
        val configPath = workdir.resolve(".opencode").resolve("opencode.json")
        Files.createDirectories(configPath.parent)
        val backupPath = if (Files.exists(configPath)) {
            val backup = Files.createTempFile(configPath.parent, "opencode.", ".json.bak")
            Files.move(configPath, backup, StandardCopyOption.REPLACE_EXISTING)
            backup
        } else {
            null
        }
        Files.writeString(configPath, configJson)
        return EphemeralOpenCodeConfig(configPath = configPath, backupPath = backupPath)
    }

    private fun restoreEphemeralOpenCodeConfig(config: EphemeralOpenCodeConfig?) {
        if (config == null) return
        if (config.backupPath != null) {
            runCatching { Files.deleteIfExists(config.configPath) }
            runCatching {
                Files.move(config.backupPath, config.configPath, StandardCopyOption.REPLACE_EXISTING)
            }
        } else {
            runCatching { Files.deleteIfExists(config.configPath) }
            runCatching { Files.deleteIfExists(config.configPath.parent) }
        }
    }

    private fun ephemeralOpenCodeConfigJson(context: ExecutionContext): String? {
        return when (context.parameters["ephemeralOpencodeProfile"]?.trim()) {
            "planning-only" -> planningOnlyOpenCodeConfigJson(context)
            null, "" -> null
            else -> null
        }
    }

    private fun planningOnlyOpenCodeConfigJson(context: ExecutionContext): String {
        val agentName = context.parameters["agent"]
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: "cotor-ceo-planner"
        val model = context.parameters["model"]
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: context.environment["OPENCODE_MODEL"]
                ?.trim()
                ?.takeIf { it.isNotBlank() }
            ?: OpenCodeDefaults.DEFAULT_MODEL

        fun jsonString(value: String): String = value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")

        return """
            {
              "${'$'}schema": "https://opencode.ai/config.json",
              "tools": {
                "read": false,
                "write": false,
                "edit": false,
                "bash": false,
                "grep": false,
                "glob": false,
                "list": false,
                "task": false,
                "task_*": false
              },
              "permission": {
                "question": "deny",
                "task": "deny",
                "edit": "deny",
                "bash": "deny",
                "webfetch": "deny",
                "external_directory": "deny"
              },
              "agent": {
                "${jsonString(agentName)}": {
                  "model": "${jsonString(model)}",
                  "mode": "primary",
                  "tools": {
                    "read": false,
                    "write": false,
                    "edit": false,
                    "bash": false,
                    "grep": false,
                    "glob": false,
                    "list": false,
                    "task": false,
                    "task_*": false
                  },
                  "permission": {
                    "question": "deny",
                    "task": "deny",
                    "edit": "deny",
                    "bash": "deny",
                    "webfetch": "deny",
                    "external_directory": "deny"
                  },
                  "prompt": "You are Cotor's CEO planning-only agent. Do not inspect files, do not call tools, and do not modify the repository. Return only the requested fenced JSON planning block."
                }
              }
            }
        """.trimIndent()
    }

    private suspend fun discoverFallbackOpenCodeModel(
        processManager: ProcessManager,
        context: ExecutionContext,
        rejectedModel: String
    ): String? {
        if (OpenCodeDefaults.isLocalOllamaModel(rejectedModel)) return null
        val models = discoverAvailableOpenCodeModels(processManager, context)
        if (models.isEmpty()) return null
        listOf(
            "deepseek/deepseek-v4-flash",
            OpenCodeDefaults.DEEPSEEK_FLASH_MODEL,
            "deepseek/deepseek-chat"
        ).firstOrNull { candidate ->
            candidate != rejectedModel && candidate in models
        }?.let { return it }
        return models.firstOrNull { it != rejectedModel && it.endsWith("-free") }
            ?: models.firstOrNull { it != rejectedModel }
    }

    private suspend fun resolvePreferredOpenCodeModel(
        processManager: ProcessManager,
        context: ExecutionContext,
        requestedModel: String
    ): String {
        if (OpenCodeDefaults.isLocalOllamaModel(requestedModel)) {
            return requestedModel
        }
        val models = discoverAvailableOpenCodeModels(processManager, context)
        if (models.isEmpty() || requestedModel in models) {
            return requestedModel
        }
        return models.firstOrNull { it.endsWith("-free") } ?: models.first()
    }

    private suspend fun discoverAvailableOpenCodeModels(
        processManager: ProcessManager,
        context: ExecutionContext
    ): List<String> {
        val result = processManager.executeProcess(
            command = listOf("opencode", "models"),
            input = null,
            environment = context.environment,
            timeout = minOf(context.timeout, 10_000),
            workingDirectory = context.workingDirectory,
            onStart = null
        )
        if (!result.isSuccess) return emptyList()
        return result.stdout.lineSequence()
            .map { it.trim() }
            .filter(OpenCodeDefaults::isSelectableModel)
            .toList()
    }

    private fun ensureLocalOllamaModelAvailable(model: String, context: ExecutionContext) {
        val tag = OpenCodeDefaults.ollamaTagForOpenCodeModel(model) ?: return
        val baseUrl = LocalModelDefaults.normalizeBaseUrl(
            context.parameters["ollamaBaseUrl"] ?: context.parameters["baseUrl"],
            LocalModelDefaults.OLLAMA_BASE_URL
        )
        val response = runCatching {
            val request = HttpRequest.newBuilder(URI.create("$baseUrl/api/tags"))
                .timeout(Duration.ofMillis(minOf(context.timeout, 2_000).coerceAtLeast(1_000L)))
                .GET()
                .build()
            httpClient.send(request, HttpResponse.BodyHandlers.ofString())
        }.getOrElse { cause ->
            throw AgentExecutionException("LOCAL_GEMMA_MODEL_MISSING: could not reach local Ollama at $baseUrl (${cause.message}).")
        }
        if (response.statusCode() !in 200..299) {
            throw AgentExecutionException("LOCAL_GEMMA_MODEL_MISSING: local Ollama at $baseUrl returned ${response.statusCode()}.")
        }
        val models = runCatching {
            json.parseToJsonElement(response.body()).jsonObject["models"]?.jsonArray
                ?.mapNotNull { item ->
                    val obj = item.jsonObject
                    val remoteHost = obj["remote_host"]?.jsonPrimitive?.contentOrNull
                    val name = obj["name"]?.jsonPrimitive?.contentOrNull
                        ?: obj["model"]?.jsonPrimitive?.contentOrNull
                    name.takeIf { LocalModelDefaults.isLocalOllamaTag(it, remoteHost) }
                }
                ?.mapNotNull(LocalModelDefaults::normalizeModel)
                ?.distinct()
                ?: emptyList()
        }.getOrDefault(emptyList())
        if (tag !in models) {
            throw AgentExecutionException("LOCAL_GEMMA_MODEL_MISSING: local Ollama model $tag was not discovered.")
        }
    }

    private fun extractOpenCodeError(result: ProcessResult): String? {
        val combined = listOf(result.stdout, result.stderr)
            .filter { it.isNotBlank() }
            .joinToString("\n")
            .trim()
        if (combined.isBlank()) return null
        Regex("Model not found: [^\\s\"]+")
            .find(combined)
            ?.value
            ?.let { return it }
        classifyFatalOpenCodeRuntimeLog(combined)?.let { return it }
        val json = Json { ignoreUnknownKeys = true }
        fun extract(element: JsonElement): String? = when (element) {
            is JsonArray -> element.firstNotNullOfOrNull(::extract)
            is JsonObject -> {
                if (element["type"]?.jsonPrimitive?.contentOrNull?.equals("error", ignoreCase = true) == true) {
                    element["error"]?.let(::extract)
                        ?: element["message"]?.jsonPrimitive?.contentOrNull
                } else {
                    element["data"]?.let(::extract)
                        ?: element["message"]?.jsonPrimitive?.contentOrNull
                }
            }
            is JsonPrimitive -> element.contentOrNull
            else -> null
        }
        runCatching { extract(json.parseToJsonElement(combined)) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
        return combined.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() && (it.startsWith("{") || it.startsWith("[")) }
            .mapNotNull { line -> runCatching { extract(json.parseToJsonElement(line)) }.getOrNull() }
            .firstOrNull { it.isNotBlank() }
    }

    private fun normalizeLocalOllamaExecutionError(error: String, requestedModel: String?): String {
        if (
            requestedModel != null &&
            OpenCodeDefaults.isLocalOllamaModel(requestedModel) &&
            error.contains("does not support tools", ignoreCase = true)
        ) {
            return "LOCAL_GEMMA_TOOLS_UNSUPPORTED: $requestedModel is available in local Ollama, " +
                "but it does not support the OpenCode tool calls required for code editing. $error"
        }
        return error
    }

    private fun isOpenCodePostTextSerializationError(error: String): Boolean =
        error.contains("[DecimalError]", ignoreCase = true) &&
            error.contains("Invalid argument", ignoreCase = true)

    private fun isOpenCodeProviderRateLimit(error: String): Boolean =
        error.contains("FreeUsageLimitError", ignoreCase = true) ||
            error.contains("rate limit exceeded", ignoreCase = true) ||
            error.contains("retry-after", ignoreCase = true)

    private fun classifyFatalOpenCodeRuntimeLog(chunk: String): String? {
        if (isOpenCodeInteractivePermissionRequest(chunk)) {
            return "OPENCODE_PERMISSION_BLOCKED: OpenCode requested interactive permission during noninteractive execution."
        }
        if (!isOpenCodeProviderRateLimit(chunk)) return null
        val retryAfter = Regex("""retry-after["'\s:=]+(\d+)""", RegexOption.IGNORE_CASE)
            .find(chunk)
            ?.groupValues
            ?.getOrNull(1)
        return buildString {
            append("OPENCODE_RATE_LIMIT: OpenCode provider returned a rate limit during execution")
            retryAfter?.let { append(" (retry-after=${it}s)") }
            append(".")
        }
    }

    private fun isOpenCodeInteractivePermissionRequest(chunk: String): Boolean {
        val lower = chunk.lowercase()
        return lower.contains("permission.asked") ||
            (lower.contains("external_directory") && lower.contains("permission") && lower.contains("ask")) ||
            (lower.contains("service=permission") && lower.contains("ask"))
    }

    private fun containsStructuredOpenCodeEvents(rawOutput: String): Boolean =
        rawOutput.lineSequence().any { line ->
            val trimmed = line.trim()
            trimmed.startsWith("{\"type\":\"") ||
                trimmed.contains("\"sessionID\"") ||
                trimmed.contains("\"messageID\"")
        }

    private fun parseOpenCodeJsonOutput(rawOutput: String): String {
        if (rawOutput.isBlank()) return rawOutput

        val json = Json { ignoreUnknownKeys = true }
        val textParts = linkedSetOf<String>()
        var parsedStructuredEvent = false

        fun collectText(element: JsonElement) {
            when (element) {
                is JsonArray -> element.forEach(::collectText)
                is JsonObject -> {
                    if (
                        element["type"] != null ||
                        element["role"] != null ||
                        element["part"] != null ||
                        element["sessionID"] != null ||
                        element["callID"] != null
                    ) {
                        parsedStructuredEvent = true
                    }
                    val type = element["type"]?.jsonPrimitive?.contentOrNull?.lowercase()
                    if (type == "tool_use" || type == "step_start") {
                        return
                    }
                    extractTextFromEvent(element)
                        .takeIf { it.isNotBlank() }
                        ?.let { textParts += normalizeOpenCodeText(it) }
                    val part = element["part"]
                    if (part is JsonObject) {
                        val partType = part["type"]?.jsonPrimitive?.contentOrNull?.lowercase()
                        if (partType != "tool") {
                            extractTextFromEvent(part)
                                .takeIf { it.isNotBlank() }
                                ?.let { textParts += normalizeOpenCodeText(it) }
                        }
                    }
                }
                else -> Unit
            }
        }

        val parsedWhole = runCatching {
            collectText(json.parseToJsonElement(rawOutput.trim()))
        }.isSuccess
        if (!parsedWhole) {
            rawOutput.lineSequence()
                .map { it.trim() }
                .filter { it.isNotBlank() && (it.startsWith("{") || it.startsWith("[")) }
                .forEach { line ->
                    runCatching { collectText(json.parseToJsonElement(line)) }
                }
        }

        return textParts
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
            .ifBlank { if (parsedStructuredEvent) "" else rawOutput }
    }

    private fun extractTextFromEvent(event: JsonObject): String {
        val contentFields = listOf("content", "text", "message", "output", "summary")
        for (field in contentFields) {
            val value = event[field]
            if (value is JsonPrimitive && value.isString) {
                return value.content
            }
            if (value is JsonObject) {
                val nested = extractTextFromEvent(value)
                if (nested.isNotBlank()) return nested
            }
            if (value is JsonArray) {
                val nested = value.joinToString("\n") { element ->
                    when (element) {
                        is JsonPrimitive -> if (element.isString) element.content else ""
                        is JsonObject -> extractTextFromEvent(element)
                        else -> ""
                    }
                }.trim()
                if (nested.isNotBlank()) return nested
            }
        }
        return ""
    }

    private fun normalizeOpenCodeText(text: String): String =
        text.lineSequence()
            .map { it.trimEnd() }
            .filter { line ->
                val trimmed = line.trim()
                trimmed.isNotBlank() &&
                    !trimmed.startsWith("{\"type\"") &&
                    !trimmed.contains("\"sessionID\"") &&
                    !trimmed.contains("\"callID\"") &&
                    !trimmed.contains("\"tool\"") &&
                    !trimmed.contains("\"command\"")
            }
            .joinToString("\n")
            .trim()

    override fun validateInput(input: String?): ValidationResult {
        if (input.isNullOrBlank()) {
            return ValidationResult.Failure(listOf("Input prompt is required for OpenCode"))
        }
        return ValidationResult.Success
    }
}
