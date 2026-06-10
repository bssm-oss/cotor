package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class SkillModelsTest : FunSpec({
    test("skill catalog names are unique") {
        val names = skillCatalog().map { it.name }

        names.distinct().size shouldBe names.size
    }

    test("marketing catalog advertises Threads and Product Hunt publishing skills") {
        val names = skillCatalog().map { it.name }

        names.contains("threads-publisher") shouldBe true
        names.contains("producthunt-publisher") shouldBe true
    }
})
