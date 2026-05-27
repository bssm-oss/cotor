package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldNotContain
import io.kotest.matchers.shouldBe
import java.nio.file.Path

class ClaudePluginTest : FunSpec({
    test("passes prompt through stdin instead of argv") {
        val plugin = ClaudePlugin()
        val processManager = RecordingClaudeProcessManager()

        val result = plugin.execute(
            ExecutionContext(
                agentName = "claude",
                input = "large prompt with repo context",
                timeout = 1_000,
                parameters = mapOf("model" to "sonnet"),
                environment = emptyMap()
            ),
            processManager
        )

        result.output shouldBe "claude ok"
        processManager.command.shouldNotContain("large prompt with repo context")
        processManager.command shouldBe listOf("claude", "--dangerously-skip-permissions", "--print", "--model", "sonnet")
        processManager.input shouldBe "large prompt with repo context"
    }
})

private class RecordingClaudeProcessManager : ProcessManager {
    var command: List<String> = emptyList()
    var input: String? = null

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
        return ProcessResult(exitCode = 0, stdout = "claude ok", stderr = "", isSuccess = true, processId = 42L)
    }
}
