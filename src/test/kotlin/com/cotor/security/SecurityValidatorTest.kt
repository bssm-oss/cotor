package com.cotor.security

import com.cotor.model.SecurityConfig
import com.cotor.model.SecurityException
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import org.slf4j.LoggerFactory
import java.nio.file.Files
import kotlin.io.path.createSymbolicLinkPointingTo

class SecurityValidatorTest : FunSpec({
    test("default security config is defensive for direct service construction") {
        val config = defaultSecurityConfig()

        config.useWhitelist shouldBe true
        config.enablePathValidation shouldBe true
        config.allowedExecutables.contains("opencode") shouldBe true
        config.allowedExecutables.contains("graphify") shouldBe true
    }

    test("default executable directory expansion includes symlink target directory") {
        val targetDir = Files.createTempDirectory("cotor-codex-package")
        val binDir = Files.createTempDirectory("cotor-codex-bin")
        val executable = targetDir.resolve("codex.js").toFile()
        executable.writeText("#!/usr/bin/env node\n")
        executable.setExecutable(true)
        val link = binDir.resolve("codex")
        link.createSymbolicLinkPointingTo(executable.toPath())

        executableAllowedDirectories(link).toSet() shouldBe setOf(binDir, targetDir)
    }

    test("command whitelist accepts absolute executable path by basename") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("qwen")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        validator.validateCommand(listOf("/opt/homebrew/bin/qwen", "{input}"))
    }

    test("command whitelist rejects executable outside allowlist") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("qwen")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validateCommand(listOf("sh", "-c", "id"))
        }
    }

    test("command validation rejects shell interpreter execution even when shell is allowlisted") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("sh")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validateCommand(listOf("sh", "-c", "id"))
        }
    }

    test("command validation rejects combined shell execution flags") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("bash", "zsh", "pwsh")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        listOf(
            listOf("bash", "-lc", "id"),
            listOf("zsh", "-ec", "id"),
            listOf("pwsh", "-EncodedCommand", "SQBk")
        ).forEach { command ->
            shouldThrow<SecurityException> {
                validator.validateCommand(command)
            }
        }
    }

    test("command validation blocks destructive commands instead of only warning") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(useWhitelist = false),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validateCommand(listOf("rm", "-rf", "/tmp/cotor-test"))
        }
    }

    test("command validation allows markdown and comparison text in argv arguments") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("graphify")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        validator.validateCommand(
            listOf(
                "graphify",
                "explain",
                "Fix the bug where x > 0, render <div>, and preserve A | B markdown table text."
            )
        )
    }

    test("command validation rejects newline and nul bytes in argv arguments") {
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedExecutables = setOf("graphify")),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validateCommand(listOf("graphify", "explain", "bad\nargument"))
        }
        shouldThrow<SecurityException> {
            validator.validateCommand(listOf("graphify", "explain", "bad\u0000argument"))
        }
    }

    test("command validation checks resolved absolute path against allowed directories") {
        val blockedDir = Files.createTempDirectory("cotor-blocked-bin")
        val executable = blockedDir.resolve("qwen").toFile()
        executable.writeText("#!/bin/sh\nexit 0\n")
        executable.setExecutable(true)
        val allowedDir = Files.createTempDirectory("cotor-allowed-bin")
        val validator = DefaultSecurityValidator(
            SecurityConfig(
                allowedExecutables = setOf("qwen"),
                allowedDirectories = listOf(allowedDir)
            ),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validateCommand(listOf(executable.absolutePath))
        }
    }

    test("command validation accepts allowlisted executable through allowed symlink target directory") {
        val targetDir = Files.createTempDirectory("cotor-homebrew-cellar")
        val binDir = Files.createTempDirectory("cotor-homebrew-bin")
        val executable = targetDir.resolve("git").toFile()
        executable.writeText("#!/bin/sh\nexit 0\n")
        executable.setExecutable(true)
        val link = binDir.resolve("git")
        link.createSymbolicLinkPointingTo(executable.toPath())
        val validator = DefaultSecurityValidator(
            SecurityConfig(
                allowedExecutables = setOf("git"),
                allowedDirectories = listOf(binDir, targetDir)
            ),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        validator.validateCommand(listOf(link.toString(), "status"))
    }

    test("path validation rejects symbolic link cycles") {
        val allowedDir = Files.createTempDirectory("cotor-symlink-cycle")
        val link = allowedDir.resolve("self")
        link.createSymbolicLinkPointingTo(link)
        val validator = DefaultSecurityValidator(
            SecurityConfig(allowedDirectories = listOf(allowedDir)),
            LoggerFactory.getLogger("SecurityValidatorTest")
        )

        shouldThrow<SecurityException> {
            validator.validatePath(link)
        }
    }
})
