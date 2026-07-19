package com.follow.clash.service

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal enum class EventOfferResult {
    ACCEPTED,
    ACCEPTED_AFTER_EVICTION,
    COALESCED,
    DROPPED,
    CLOSED,
}

private data class PendingEvent<T>(
    val value: T,
    val required: Boolean,
    val coalesceKey: String?,
    val collapseGroup: String?,
    val collapsedEvent: T?,
)

internal class EventForwarder<T>(
    private val generation: Long,
    private val activeGeneration: AtomicLong,
    scope: CoroutineScope,
    private val capacity: Int,
    onConsumeError: (Throwable) -> Unit = {},
    consume: suspend (T) -> Unit,
) {
    private val lock = ReentrantLock()
    private val pending = ArrayDeque<PendingEvent<T>>(capacity)
    private val wakeUp = Channel<Unit>(Channel.CONFLATED)
    private var closed = false
    private val job: Job = scope.launch {
        while (true) {
            val event = poll()
            if (event == null) {
                if (wakeUp.receiveCatching().isClosed) break
                continue
            }
            if (!isCurrent()) break
            try {
                consume(event.value)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                onConsumeError(error)
            }
        }
    }

    init {
        require(capacity > 0)
        job.invokeOnCompletion {
            lock.withLock {
                closed = true
                pending.clear()
            }
            wakeUp.close()
        }
    }

    fun send(
        event: T,
        required: Boolean,
        coalesceKey: String? = null,
        collapseGroup: String? = null,
        collapsedEvent: T? = null,
    ): EventOfferResult {
        var evicted = false
        var coalesced = false
        lock.withLock {
            if (!isOpenLocked()) return EventOfferResult.CLOSED
            if (required && coalesceKey != null) {
                val sameKey = pending.indexOfFirst { it.coalesceKey == coalesceKey }
                if (sameKey >= 0) {
                    pending[sameKey] = PendingEvent(
                        event,
                        true,
                        coalesceKey,
                        collapseGroup,
                        collapsedEvent,
                    )
                    return EventOfferResult.COALESCED
                }
            }
            if (pending.size >= capacity) {
                val bestEffortIndex = pending.indexOfFirst { !it.required }
                if (bestEffortIndex >= 0 && required) {
                    pending.removeAt(bestEffortIndex)
                    evicted = true
                } else if (!required) {
                    return EventOfferResult.DROPPED
                } else if (collapseGroup != null && collapsedEvent != null) {
                    pending.removeAll { it.collapseGroup == collapseGroup }
                    if (pending.size >= capacity) return EventOfferResult.DROPPED
                    pending.addLast(
                        PendingEvent(
                            collapsedEvent,
                            true,
                            "$collapseGroup:*",
                            collapseGroup,
                            collapsedEvent,
                        ),
                    )
                    wakeUp.trySend(Unit)
                    return EventOfferResult.COALESCED
                } else if (collapseExistingGroup()) {
                    coalesced = true
                } else {
                    return EventOfferResult.DROPPED
                }
            }
            pending.addLast(
                PendingEvent(event, required, coalesceKey, collapseGroup, collapsedEvent),
            )
        }
        wakeUp.trySend(Unit)
        return if (coalesced) {
            EventOfferResult.COALESCED
        } else if (evicted) {
            EventOfferResult.ACCEPTED_AFTER_EVICTION
        } else {
            EventOfferResult.ACCEPTED
        }
    }

    fun isCurrent(): Boolean = activeGeneration.get() == generation

    fun close() {
        lock.withLock {
            if (closed) return
            closed = true
            pending.clear()
        }
        wakeUp.close()
        job.cancel()
    }

    suspend fun join() {
        job.join()
    }

    fun pendingCount(): Int = lock.withLock { pending.size }

    private fun poll(): PendingEvent<T>? = lock.withLock {
        if (pending.isEmpty()) return null
        pending.removeFirst()
    }

    private fun isOpenLocked(): Boolean = !closed && isCurrent()

    private fun collapseExistingGroup(): Boolean {
        val candidate = pending.firstNotNullOfOrNull { event ->
            val group = event.collapseGroup ?: return@firstNotNullOfOrNull null
            val replacement = event.collapsedEvent ?: return@firstNotNullOfOrNull null
            val count = pending.count { it.collapseGroup == group }
            if (count > 1) Triple(group, replacement, count) else null
        } ?: return false
        pending.removeAll { it.collapseGroup == candidate.first }
        pending.addLast(
            PendingEvent(
                candidate.second,
                true,
                "${candidate.first}:*",
                candidate.first,
                candidate.second,
            ),
        )
        return candidate.third > 1
    }
}

internal fun isRequiredCoreEvent(value: String): Boolean =
    value.contains("\"eventRequired\":true")

internal data class CoreEventQueueMetadata(
    val required: Boolean,
    val type: String?,
    val key: String?,
)
