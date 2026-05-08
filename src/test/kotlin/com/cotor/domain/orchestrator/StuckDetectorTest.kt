package com.cotor.domain.orchestrator

import com.cotor.model.AgentResult
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class StuckDetectorTest : FunSpec({
    test("signals same repeated error before max iteration exhaustion") {
        val detector = StuckDetector(sameErrorRepeat = 2)
        val first = AgentResult("worker", false, null, "compile failed on Foo.kt:10", 1, emptyMap())
        val second = first.copy(duration = 2)

        detector.record(first) shouldBe null
        detector.record(second) shouldBe StuckSignal.SAME_ERROR
    }

    test("signals revision loop when failures keep changing") {
        val detector = StuckDetector(sameErrorRepeat = 3, revisionLoop = 3)

        detector.record(AgentResult("worker", false, null, "first", 1, emptyMap())) shouldBe null
        detector.record(AgentResult("worker", false, null, "second", 1, emptyMap())) shouldBe null
        detector.record(AgentResult("worker", false, null, "third", 1, emptyMap())) shouldBe StuckSignal.REVISION_LOOP
    }
})
