package com.cotor.data.plugin

import com.cotor.data.process.ProcessManager
import com.cotor.model.ExecutionContext
import com.cotor.model.ProcessResult
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import java.nio.file.Path

class CommandPluginTest : FunSpec({
    test("command plugin delegates command guarding to the provided process manager") {
        val processManager = BlockingProcessManager()
        val plugin = CommandPlugin()

        val error = shouldThrow<IllegalStateException> {
            plugin.execute(
                ExecutionContext(
                    agentName = "command",
                    input = null,
                    parameters = mapOf("argvJson" to "[\"sh\",\"-c\",\"id\"]"),
                    environment = emptyMap(),
                    timeout = 1000
                ),
                processManager
            )
        }

        error.message shouldBe "blocked by process manager guard"
    }

    test("command plugin passes substituted input as literal argv") {
        val processManager = RecordingProcessManager()
        val plugin = CommandPlugin()

        plugin.execute(
            ExecutionContext(
                agentName = "command",
                input = "literal ; | < > input",
                parameters = mapOf("argvJson" to "[\"/opt/homebrew/bin/qwen\",\"{input}\"]"),
                environment = emptyMap(),
                timeout = 1000
            ),
            processManager
        )

        processManager.commands.single().shouldContainExactly(listOf("/opt/homebrew/bin/qwen", "literal ; | < > input"))
    }
})

private class RecordingProcessManager : ProcessManager {
    val commands = mutableListOf<List<String>>()

    override suspend fun executeProcess(
        command: List<String>,
        input: String?,
        environment: Map<String, String>,
        timeout: Long,
        workingDirectory: Path?,
        onStart: ((Long) -> Unit)?
    ): ProcessResult {
        commands += command
        return ProcessResult(exitCode = 0, stdout = "ok", stderr = "", isSuccess = true)
    }
}

private class BlockingProcessManager : ProcessManager {
    override suspend fun executeProcess(
        command: List<String>,
        input: String?,
        environment: Map<String, String>,
        timeout: Long,
        workingDirectory: Path?,
        onStart: ((Long) -> Unit)?
    ): ProcessResult {
        throw IllegalStateException("blocked by process manager guard")
    }
}
