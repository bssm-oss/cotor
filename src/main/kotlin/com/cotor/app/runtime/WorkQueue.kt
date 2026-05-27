package com.cotor.app.runtime

import java.util.concurrent.ConcurrentLinkedQueue

class WorkQueue {
    private val commands = ConcurrentLinkedQueue<RuntimeCommand>()

    fun enqueue(command: RuntimeCommand) {
        commands.add(command)
    }

    fun isEmpty(): Boolean = commands.isEmpty()

    suspend fun drain(executor: suspend (RuntimeCommand) -> Unit) {
        while (true) {
            val command = commands.poll() ?: return
            executor(command)
        }
    }
}
