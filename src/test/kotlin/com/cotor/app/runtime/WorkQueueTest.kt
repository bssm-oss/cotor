package com.cotor.app.runtime

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactlyInAnyOrder
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

class WorkQueueTest : FunSpec({
    test("enqueue and drain tolerate concurrent producers") {
        val queue = WorkQueue()
        val expected = (0 until 200).map { "issue-$it" }

        runBlocking {
            expected.chunked(20).map { chunk ->
                async(Dispatchers.Default) {
                    chunk.forEach { issueId ->
                        queue.enqueue(RuntimeCommand.StartIssue(issueId))
                    }
                }
            }.awaitAll()
        }

        val drained = mutableListOf<String>()
        runBlocking {
            withContext(Dispatchers.Default) {
                queue.drain { command ->
                    drained += (command as RuntimeCommand.StartIssue).issueId
                }
            }
        }

        drained.size shouldBe expected.size
        drained shouldContainExactlyInAnyOrder expected
    }

    test("drain remains safe while producers enqueue additional commands") {
        val queue = WorkQueue()
        val initial = (0 until 100).map { "initial-$it" }
        val late = (0 until 100).map { "late-$it" }
        initial.forEach { queue.enqueue(RuntimeCommand.StartIssue(it)) }

        val drained = mutableListOf<String>()
        runBlocking {
            val drainer = async(Dispatchers.Default) {
                queue.drain { command ->
                    drained += (command as RuntimeCommand.StartIssue).issueId
                    delay(1L)
                }
            }
            val producer = async(Dispatchers.Default) {
                late.forEach { issueId ->
                    queue.enqueue(RuntimeCommand.StartIssue(issueId))
                    delay(1L)
                }
            }
            awaitAll(drainer, producer)
            queue.drain { command ->
                drained += (command as RuntimeCommand.StartIssue).issueId
            }
        }

        drained.size shouldBe initial.size + late.size
        drained shouldContainExactlyInAnyOrder initial + late
    }
})
