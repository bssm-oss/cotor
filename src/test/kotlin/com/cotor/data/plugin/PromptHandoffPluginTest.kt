package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import java.nio.file.Path

class PromptHandoffPluginTest : FunSpec({
    test("passes copilot prompt through a prompt file instead of argv") {
        val prompt = "large prompt with repo context and token-like value"
        val processManager = RecordingPromptProcessManager(readPromptFileFromCommand = true)

        val result = CopilotPlugin().execute(
            ExecutionContext(
                agentName = "copilot",
                input = prompt,
                timeout = 1_000,
                parameters = emptyMap(),
                environment = emptyMap()
            ),
            processManager
        )

        result.output shouldBe "ok"
        processManager.command.contains(prompt) shouldBe false
        processManager.command.joinToString(" ").contains(prompt) shouldBe false
        processManager.input shouldBe null
        processManager.promptFileContent shouldBe prompt
        processManager.command.contains("--add-dir") shouldBe true
    }

    test("passes gemini prompt through stdin instead of argv") {
        val prompt = "large prompt with repo context"
        val processManager = RecordingPromptProcessManager()

        val result = GeminiPlugin().execute(
            ExecutionContext(
                agentName = "gemini",
                input = prompt,
                timeout = 1_000,
                parameters = emptyMap(),
                environment = emptyMap()
            ),
            processManager
        )

        result.output shouldBe "ok"
        processManager.command shouldBe listOf("gemini", "--yolo", "--prompt", "Execute the task provided on stdin.")
        processManager.command.contains(prompt) shouldBe false
        processManager.input shouldBe prompt
    }

    test("passes cursor prompt through a prompt file instead of argv") {
        val prompt = "large prompt with repo context"
        val processManager = RecordingPromptProcessManager(readPromptFileFromCommand = true)

        val result = CursorPlugin().execute(
            ExecutionContext(
                agentName = "cursor",
                input = prompt,
                timeout = 1_000,
                parameters = emptyMap(),
                environment = emptyMap()
            ),
            processManager
        )

        result.output shouldBe "ok"
        processManager.command.contains(prompt) shouldBe false
        processManager.command.joinToString(" ").contains(prompt) shouldBe false
        processManager.input shouldBe null
        processManager.promptFileContent shouldBe prompt
    }
})

private class RecordingPromptProcessManager(
    private val readPromptFileFromCommand: Boolean = false
) : ProcessManager {
    var command: List<String> = emptyList()
    var input: String? = null
    var promptFileContent: String? = null

    override suspend fun executeProcess(
        command: List<String>,
        input: String?,
        environment: Map<String, String>,
        timeout: Long,
        workingDirectory: Path?,
        onStart: ((Long) -> Unit)?
    ): ProcessResult {
        this.command = command
        this.input = input
        if (readPromptFileFromCommand) {
            promptFileContent = command
                .asSequence()
                .mapNotNull(::extractPromptFilePath)
                .firstOrNull()
                ?.let(Files::readString)
        }
        return ProcessResult(exitCode = 0, stdout = "ok", stderr = "", isSuccess = true, processId = 123L)
    }

    private fun extractPromptFilePath(value: String): Path? {
        val match = Regex("(/\\S+/prompt\\.md)").find(value) ?: return null
        return Path.of(match.value)
    }
}
