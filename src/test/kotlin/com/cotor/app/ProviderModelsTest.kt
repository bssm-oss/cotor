package com.cotor.app

import com.cotor.model.LocalModelDefaults
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.shouldBe

class ProviderModelsTest : FunSpec({
    test("provider catalog exposes agent-facing aliases for readiness checks") {
        val providers = providerCatalog()

        providers.map { it.id }.distinct().size shouldBe providers.size
        providers.first { it.id == "codex-cli" }.aliases shouldContainAll listOf("codex", "codex-exec", "codex-oauth")
        providers.first { it.id == "claude-code" }.aliases shouldContainAll listOf("claude")
        providers.first { it.id == "ollama" }.aliases shouldContainAll listOf("gemma4")
        providers.first { it.id == "lm-studio" }.aliases shouldContainAll listOf("lmstudio")
    }

    test("provider id matching accepts canonical ids and aliases case-insensitively") {
        val codex = providerCatalog().first { it.id == "codex-cli" }
        val lmStudio = providerCatalog().first { it.id == "lm-studio" }

        codex.matchesIdOrAlias("codex-cli") shouldBe true
        codex.matchesIdOrAlias("CODEX-OAUTH") shouldBe true
        lmStudio.matchesIdOrAlias("lmstudio") shouldBe true
        codex.matchesIdOrAlias("missing") shouldBe false
    }

    test("provider lookup accepts agent-facing aliases") {
        findProviderByIdOrAlias(" codex ")?.id shouldBe "codex-cli"
        findProviderByIdOrAlias("codex-exec")?.id shouldBe "codex-cli"
        findProviderByIdOrAlias("codex-oauth")?.id shouldBe "codex-cli"
        findProviderByIdOrAlias("CLAUDE")?.id shouldBe "claude-code"
        findProviderByIdOrAlias("gemma4")?.id shouldBe "ollama"
        findProviderByIdOrAlias(" ") shouldBe null
        findProviderByIdOrAlias("missing") shouldBe null
    }

    test("direct chat provider catalog reuses provider aliases and UI defaults") {
        val providers = directChatProviderCatalog()

        providers.map { it.id }.distinct().size shouldBe providers.size
        val ollama = providers.first { it.id == "ollama" }
        val lmStudio = providers.first { it.id == "lmstudio" }
        ollama.supportsModelDiscovery shouldBe true
        ollama.defaultModel shouldBe LocalModelDefaults.GEMMA4_MODEL
        lmStudio.providerId shouldBe "lm-studio"
        lmStudio.defaultModel shouldBe LocalModelDefaults.GEMMA4_12B_HUGGING_FACE_INSTRUCT_MODEL
        providers.first { it.id == "claude-cli" }.allowsBaseUrl shouldBe false

        findDirectChatProvider("lm-studio")?.id shouldBe "lmstudio"
        findDirectChatProvider("lmstudio")?.id shouldBe "lmstudio"
        findDirectChatProvider("claude")?.id shouldBe "claude-cli"
        findDirectChatProvider("missing") shouldBe null
    }
})
