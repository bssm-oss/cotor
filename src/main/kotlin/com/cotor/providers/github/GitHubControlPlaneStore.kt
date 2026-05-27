package com.cotor.providers.github

import com.cotor.app.defaultDesktopAppHome
import com.cotor.storage.writeTextAtomically
import kotlinx.serialization.json.Json
import java.nio.file.Path
import kotlin.io.path.exists
import kotlin.io.path.readText

class GitHubControlPlaneStore(
    private val appHomeProvider: () -> Path = { defaultDesktopAppHome() }
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun file(): Path =
        appHomeProvider().resolve("providers").resolve("github").resolve("state.json")

    @Synchronized
    fun load(): GitHubProviderState {
        val file = file()
        if (!file.exists()) {
            return GitHubProviderState()
        }
        return runCatching {
            json.decodeFromString(GitHubProviderState.serializer(), file.readText())
        }.getOrDefault(GitHubProviderState())
    }

    @Synchronized
    fun save(state: GitHubProviderState) {
        writeState(state)
    }

    @Synchronized
    fun update(transform: (GitHubProviderState) -> GitHubProviderState): GitHubProviderState {
        val next = transform(loadUnlocked())
        writeState(next)
        return next
    }

    private fun loadUnlocked(): GitHubProviderState {
        val file = file()
        if (!file.exists()) {
            return GitHubProviderState()
        }
        return runCatching {
            json.decodeFromString(GitHubProviderState.serializer(), file.readText())
        }.getOrDefault(GitHubProviderState())
    }

    private fun writeState(state: GitHubProviderState) {
        val file = file()
        writeTextAtomically(file, json.encodeToString(GitHubProviderState.serializer(), state))
    }
}
