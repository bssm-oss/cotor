package com.cotor.data.plugin

import com.cotor.model.PluginLoadException
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import org.slf4j.LoggerFactory
import java.nio.file.Files
import kotlin.io.path.exists

class PluginLoaderTest : FunSpec({
    test("reflection loader trims and loads valid AgentPlugin classes") {
        val loader = ReflectionPluginLoader(LoggerFactory.getLogger("PluginLoaderTest"))

        val plugin = loader.loadPlugin("  com.cotor.data.plugin.EchoPlugin  ")

        plugin.metadata.name shouldBe "echo"
    }

    test("reflection loader rejects malformed class names before class loading") {
        val loader = ReflectionPluginLoader(LoggerFactory.getLogger("PluginLoaderTest"))

        val error = shouldThrow<PluginLoadException> {
            loader.loadPlugin("[Ljava.lang.String;")
        }

        error.message shouldContain "Invalid plugin class name"
    }

    test("reflection loader does not initialize classes before AgentPlugin type verification") {
        val marker = Files.createTempFile("plugin-loader-static-init", ".txt")
        Files.deleteIfExists(marker)
        System.setProperty(STATIC_INIT_MARKER_PROPERTY, marker.toString())
        val loader = ReflectionPluginLoader(LoggerFactory.getLogger("PluginLoaderTest"))

        try {
            val error = shouldThrow<PluginLoadException> {
                loader.loadPlugin("com.cotor.data.plugin.NonPluginWithStaticInitializer")
            }

            error.message shouldContain "does not implement AgentPlugin"
            marker.exists() shouldBe false
        } finally {
            System.clearProperty(STATIC_INIT_MARKER_PROPERTY)
            Files.deleteIfExists(marker)
        }
    }
})

private const val STATIC_INIT_MARKER_PROPERTY = "cotor.pluginloader.staticInitMarker"

private class NonPluginWithStaticInitializer {
    companion object {
        init {
            System.getProperty(STATIC_INIT_MARKER_PROPERTY)
                ?.let { marker -> Files.writeString(java.nio.file.Path.of(marker), "initialized") }
        }
    }
}
