package com.cotor.validation.output

/**
 * File overview for SyntaxValidationResult.
 *
 * This file belongs to the validation layer that rejects invalid pipelines before execution.
 * It groups declarations around syntax validator so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import com.cotor.data.process.destroyProcessTree
import org.slf4j.LoggerFactory
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Comparator
import java.util.concurrent.TimeUnit

data class SyntaxValidationResult(
    val isValid: Boolean,
    val message: String,
    val errors: List<String> = emptyList()
)

class SyntaxValidator internal constructor(
    private val timeoutSeconds: Long,
    private val maxOutputChars: Int,
    private val commandFactory: (String, String) -> SyntaxValidationCommand?
) {
    constructor(
        timeoutSeconds: Long = DEFAULT_SYNTAX_VALIDATION_TIMEOUT_SECONDS,
        maxOutputChars: Int = DEFAULT_SYNTAX_VALIDATION_OUTPUT_CHARS
    ) : this(timeoutSeconds, maxOutputChars, ::defaultSyntaxValidationCommand)

    private val logger = LoggerFactory.getLogger(SyntaxValidator::class.java)

    fun validate(language: String, filePath: String): SyntaxValidationResult {
        val normalizedLanguage = language.lowercase().trim()
        if (isKotlinScript(normalizedLanguage, filePath)) {
            return SyntaxValidationResult(
                false,
                "Kotlin script syntax validation is disabled",
                errors = listOf("Kotlin script syntax validation is disabled because script validation can execute code.")
            )
        }
        val command = commandFactory(normalizedLanguage, filePath)
            ?: return SyntaxValidationResult(true, "Unsupported language '$language', skipping")
        return runCommand(command)
    }

    private fun runCommand(command: SyntaxValidationCommand): SyntaxValidationResult {
        require(command.argv.isNotEmpty()) { "syntax validation command is required" }
        val outputFile = Files.createTempFile("cotor-syntax-validation-", ".log")
        var process: Process? = null
        return try {
            process = ProcessBuilder(command.argv)
                .redirectErrorStream(true)
                .redirectOutput(outputFile.toFile())
                .apply { environment().putAll(command.environment) }
                .start()
            val finished = process.waitFor(timeoutSeconds.coerceAtLeast(1), TimeUnit.SECONDS)
            if (!finished) {
                destroyProcessTree(process, logger = logger)
                return SyntaxValidationResult(
                    false,
                    "${command.label} syntax validation timed out",
                    errors = listOf("${command.label} syntax validation timed out after ${timeoutSeconds.coerceAtLeast(1)}s")
                )
            }
            val exitCode = process.exitValue()
            val output = readBoundedSyntaxOutput(outputFile, maxOutputChars)

            if (exitCode == 0) {
                SyntaxValidationResult(true, "${command.label} syntax valid")
            } else {
                SyntaxValidationResult(false, "${command.label} syntax errors", errors = listOf(output.trim()))
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            process?.let { destroyProcessTree(it, logger = logger) }
            SyntaxValidationResult(
                false,
                "${command.label} syntax validation interrupted",
                errors = listOf("${command.label} syntax validation interrupted")
            )
        } catch (e: Exception) {
            process?.takeIf { it.isAlive }?.let { destroyProcessTree(it, logger = logger) }
            val detail = e.message ?: e::class.simpleName.orEmpty()
            logger.debug("${command.label} syntax validation failed to run: $detail")
            SyntaxValidationResult(
                false,
                "${command.label} syntax validation failed to run",
                errors = listOf("${command.label} syntax validation failed to run: $detail")
            )
        } finally {
            runCatching { Files.deleteIfExists(outputFile) }
            command.cleanupPaths.forEach { deleteRecursively(it) }
        }
    }
}

internal data class SyntaxValidationCommand(
    val argv: List<String>,
    val label: String,
    val environment: Map<String, String> = emptyMap(),
    val cleanupPaths: List<Path> = emptyList()
)

private fun defaultSyntaxValidationCommand(language: String, filePath: String): SyntaxValidationCommand? =
    when (language) {
        "python" -> SyntaxValidationCommand(
            argv = listOf("python3", "-c", PYTHON_AST_SYNTAX_CHECK, filePath),
            label = "Python"
        )
        "javascript", "js" -> SyntaxValidationCommand(
            argv = listOf("node", "--check", filePath),
            label = "JavaScript"
        )
        "typescript", "ts" -> SyntaxValidationCommand(
            argv = listOf("tsc", "--noEmit", filePath),
            label = "TypeScript"
        )
        "kotlin", "kt" -> {
            val outputDir = Files.createTempDirectory("cotor-kotlin-syntax-")
            SyntaxValidationCommand(
                argv = listOf("kotlinc", filePath, "-d", outputDir.toString()),
                label = "Kotlin",
                cleanupPaths = listOf(outputDir)
            )
        }
        else -> null
    }

private fun isKotlinScript(language: String, filePath: String): Boolean =
    language in setOf("kotlin", "kt") &&
        Path.of(filePath).fileName.toString().endsWith(".kts", ignoreCase = true)

private fun readBoundedSyntaxOutput(path: Path, maxChars: Int): String {
    val maxBytes = maxChars.coerceAtLeast(0).toLong()
    if (maxBytes == 0L) {
        return "[cotor truncated all syntax validator output]"
    }
    val size = Files.size(path)
    Files.newInputStream(path).use { input ->
        if (size > maxBytes) {
            input.skipNBytes(size - maxBytes)
            return "[cotor truncated ${size - maxBytes} bytes from syntax validator output]\n" +
                String(input.readAllBytes(), StandardCharsets.UTF_8)
        }
        return String(input.readAllBytes(), StandardCharsets.UTF_8)
    }
}

private fun deleteRecursively(path: Path) {
    if (!Files.exists(path)) return
    Files.walk(path).use { paths ->
        paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) }
    }
}

private const val PYTHON_AST_SYNTAX_CHECK =
    "import ast, pathlib, sys; path = sys.argv[1]; ast.parse(pathlib.Path(path).read_text(encoding='utf-8'), filename=path)"
private const val DEFAULT_SYNTAX_VALIDATION_TIMEOUT_SECONDS = 10L
private const val DEFAULT_SYNTAX_VALIDATION_OUTPUT_CHARS = 256_000
