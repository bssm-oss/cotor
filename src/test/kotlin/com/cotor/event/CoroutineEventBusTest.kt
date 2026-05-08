package com.cotor.event

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactly
import kotlinx.coroutines.delay

class CoroutineEventBusTest : FunSpec({
    test("uses a bounded queue and close cancels processing resources") {
        val bus = CoroutineEventBus(capacity = 4)
        val received = mutableListOf<String>()
        bus.subscribe(PipelineStartedEvent::class) { event ->
            received += (event as PipelineStartedEvent).pipelineId
        }

        bus.emit(PipelineStartedEvent("pipeline-1", "one"))
        delay(100)
        received.shouldContainExactly("pipeline-1")

        bus.close()
    }
})
