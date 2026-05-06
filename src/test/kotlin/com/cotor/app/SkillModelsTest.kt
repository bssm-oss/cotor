package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class SkillModelsTest : FunSpec({
    test("skill catalog names are unique") {
        val names = skillCatalog().map { it.name }

        names.distinct().size shouldBe names.size
    }
})
