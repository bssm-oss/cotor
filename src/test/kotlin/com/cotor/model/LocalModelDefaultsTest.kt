package com.cotor.model

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class LocalModelDefaultsTest : FunSpec({
    test("detects Gemma 4 model aliases from local model lists") {
        LocalModelDefaults.isGemma4Model("gemma4:12b") shouldBe true
        LocalModelDefaults.isGemma4Model("google/gemma-4-31b-it") shouldBe true
        LocalModelDefaults.isGemma4Model("nvidia/google/gemma_4_31b_it") shouldBe true
    }

    test("does not treat older Gemma or unrelated models as Gemma 4") {
        LocalModelDefaults.isGemma4Model("gemma3:4b") shouldBe false
        LocalModelDefaults.isGemma4Model("qwen2.5-coder:32b") shouldBe false
        LocalModelDefaults.isGemma4Model("notgemma4:latest") shouldBe false
    }

    test("detects installed Gemma family models for app-managed local fallback") {
        LocalModelDefaults.isGemmaFamilyModel("gemma4:12b") shouldBe true
        LocalModelDefaults.isGemmaFamilyModel("gemma3:4b") shouldBe true
        LocalModelDefaults.isGemmaFamilyModel("google/gemma-4-31b-it") shouldBe true
        LocalModelDefaults.isGemmaFamilyModel("notgemma4:latest") shouldBe false
    }

    test("installed Gemma 4 models are trimmed and de-duplicated in discovery order") {
        LocalModelDefaults.installedGemma4Models(
            listOf(
                " qwen2.5:3b ",
                "gemma4:12b",
                "google/gemma-4-31b-it",
                "gemma4:12b",
                "gemma3:4b"
            )
        ) shouldBe listOf("gemma4:12b", "google/gemma-4-31b-it")
    }

    test("preferred installed Gemma models keep Gemma 4 first and then fallback family models") {
        LocalModelDefaults.preferredInstalledGemmaModels(
            listOf(
                " qwen2.5:3b ",
                "gemma3:4b",
                "gemma4:12b",
                "gemma3:4b",
                "google/gemma-4-31b-it"
            )
        ) shouldBe listOf("gemma4:12b", "google/gemma-4-31b-it", "gemma3:4b")
    }

    test("preferred installed Gemma models promote Gemma 4 12B ahead of smaller or larger Gemma 4 variants") {
        LocalModelDefaults.preferredInstalledGemmaModels(
            listOf(
                "gemma4:e2b",
                "google/gemma-4-31b-it",
                "gemma4:12b",
                "google/gemma-4-12B-it",
                "gemma3:4b"
            )
        ) shouldBe listOf("gemma4:12b", "google/gemma-4-12B-it", "gemma4:e2b", "google/gemma-4-31b-it", "gemma3:4b")
    }
})
