package com.cotor.event

/**
 * File overview for EventSubscription.
 *
 * This file belongs to the eventing layer used to publish runtime activity across the product.
 * It groups declarations around event bus so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.reflect.KClass

/**
 * Interface for event bus
 */
data class EventSubscription(
    val eventType: KClass<out CotorEvent>,
    val handler: suspend (CotorEvent) -> Unit
)

interface EventBus {
    /**
     * Emit an event
     * @param event Event to emit
     */
    suspend fun emit(event: CotorEvent)

    /**
     * Subscribe to event type
     * @param eventType Type of event to subscribe to
     * @param handler Handler function for event
     * @return Subscription that can be disposed
     */
    fun subscribe(eventType: KClass<out CotorEvent>, handler: suspend (CotorEvent) -> Unit): EventSubscription

    /**
     * Unsubscribe from event type
     * @param subscription Subscription to remove
     */
    fun unsubscribe(subscription: EventSubscription)
}

/**
 * Coroutine-based event bus implementation
 */
class CoroutineEventBus(
    capacity: Int = DEFAULT_CAPACITY
) : EventBus, AutoCloseable {
    private val subscribers = ConcurrentHashMap<KClass<out CotorEvent>, MutableList<EventSubscription>>()
    private val eventChannel = Channel<CotorEvent>(capacity)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val processor = scope.launch {
        for (event in eventChannel) {
            processEvent(event)
        }
    }

    init {
        require(capacity > 0) { "Event bus capacity must be positive" }
    }

    override suspend fun emit(event: CotorEvent) {
        eventChannel.send(event)
    }

    override fun subscribe(eventType: KClass<out CotorEvent>, handler: suspend (CotorEvent) -> Unit): EventSubscription {
        val subscription = EventSubscription(eventType, handler)
        subscribers.computeIfAbsent(eventType) { CopyOnWriteArrayList() }
            .add(subscription)
        return subscription
    }

    override fun unsubscribe(subscription: EventSubscription) {
        val handlers = subscribers[subscription.eventType] ?: return
        handlers.remove(subscription)
        if (handlers.isEmpty()) {
            subscribers.remove(subscription.eventType)
        }
    }

    private suspend fun processEvent(event: CotorEvent) {
        val handlers = subscribers[event::class]?.toList() ?: return

        handlers.forEach { subscription ->
            scope.launch {
                try {
                    subscription.handler(event)
                } catch (e: Exception) {
                    // Log error but continue processing other handlers
                    println("Error processing event: ${e.message}")
                }
            }
        }
    }

    override fun close() {
        eventChannel.close()
        processor.cancel()
        scope.cancel()
        subscribers.clear()
    }

    private companion object {
        private const val DEFAULT_CAPACITY = 1024
    }
}
