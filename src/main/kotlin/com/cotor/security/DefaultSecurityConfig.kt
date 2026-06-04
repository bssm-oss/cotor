package com.cotor.security

import com.cotor.data.process.resolveExecutablePath
import com.cotor.model.SecurityConfig
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.Path

fun defaultSecurityConfig(): SecurityConfig {
    val allowedExecutables = defaultAllowedExecutables()
    return SecurityConfig(
        useWhitelist = true,
        allowedExecutables = allowedExecutables,
        allowedDirectories = defaultAllowedDirectories(allowedExecutables),
        enablePathValidation = true
    )
}

fun defaultAllowedExecutables(): Set<String> = setOf(
    "python3",
    "python",
    "node",
    "npm",
    "npx",
    "java",
    "git",
    "gh",
    "lsof",
    "claude",
    "codex",
    "copilot",
    "gemini",
    "cursor-cli",
    "opencode",
    "qwen",
    "graphify",
    "ollama",
    "swift",
    "gradle",
    "gradlew",
    "mvn",
    "mvnw",
    "pnpm",
    "yarn",
    "pytest",
    "go",
    "cargo"
)

fun defaultAllowedDirectories(allowedExecutables: Set<String> = defaultAllowedExecutables()): List<Path> {
    val pathDirectories = System.getenv("PATH")
        .orEmpty()
        .split(File.pathSeparator)
        .mapNotNull { it.trim().takeIf(String::isNotBlank) }
        .map { Path(it).toAbsolutePath().normalize() }
    val executableDirectories = allowedExecutables.mapNotNull { executable ->
        runCatching { resolveExecutablePath(executable)?.parent }.getOrNull()
    }
    val userHome = Path(System.getProperty("user.home")).toAbsolutePath().normalize()
    val conventionalDirectories = listOf(
        Path("/usr/bin"),
        Path("/bin"),
        Path("/usr/sbin"),
        Path("/sbin"),
        Path("/usr/local/bin"),
        Path("/usr/local/Cellar"),
        Path("/usr/local/opt"),
        Path("/opt/homebrew/bin"),
        Path("/opt/homebrew/Cellar"),
        Path("/opt/homebrew/opt"),
        Path("/opt/cotor"),
        userHome.resolve("Library").resolve("Python"),
        userHome.resolve("Library").resolve("Application Support").resolve("CotorDesktop")
    )
    return (pathDirectories + executableDirectories + conventionalDirectories)
        .map { it.toAbsolutePath().normalize() }
        .filter { Files.exists(it) }
        .distinct()
}
