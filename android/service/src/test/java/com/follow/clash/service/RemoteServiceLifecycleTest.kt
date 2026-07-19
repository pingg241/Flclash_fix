package com.follow.clash.service

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class RemoteServiceLifecycleTest {
    @Test
    fun lateCleanupOnlyOwnsTheDelegateItCaptured() {
        val destroyedDelegate = Any()
        val replacementDelegate = Any()

        assertTrue(ownsServiceState(destroyedDelegate, destroyedDelegate))
        assertFalse(ownsServiceState(replacementDelegate, destroyedDelegate))
    }

    @Test
    fun stoppedRuntimeStartsNewService() {
        val resolution = resolveExistingRuntimeStart(runTime = 0L)

        assertEquals(ExistingRuntimeAction.START_NEW, resolution)
    }

    @Test
    fun existingRuntimeIsRejectedWithoutTransferringOwnership() {
        assertEquals(
            ExistingRuntimeAction.REJECT,
            resolveExistingRuntimeStart(runTime = 42L),
        )
        assertTrue(ownsStartOperation("existing", "existing"))
        assertFalse(ownsStartOperation("existing", "new"))
    }

    @Test
    fun eventForwarderIsBoundedAndOrdered() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val delivered = Channel<Int>(2)
        val forwarder = EventForwarder(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 1,
        ) { value: Int ->
            if (value == 1) {
                firstStarted.complete(Unit)
                releaseFirst.await()
            }
            delivered.send(value)
        }

        try {
            assertEquals(EventOfferResult.ACCEPTED, forwarder.send(1, required = false))
            withTimeout(1_000L) { firstStarted.await() }
            assertEquals(EventOfferResult.ACCEPTED, forwarder.send(2, required = false))
            assertEquals(EventOfferResult.DROPPED, forwarder.send(3, required = false))
            releaseFirst.complete(Unit)
            assertEquals(1, withTimeout(1_000L) { delivered.receive() })
            assertEquals(2, withTimeout(1_000L) { delivered.receive() })
        } finally {
            forwarder.close()
            scope.cancel()
        }
    }

    @Test
    fun requiredEventsStayBoundedAndNonBlockingWhenConsumerStalls() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val delivered = Channel<String>(8)
        val forwarder = EventForwarder(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 4,
        ) { value: String ->
            if (value == "in-flight") {
                firstStarted.complete(Unit)
                releaseFirst.await()
            }
            delivered.send(value)
        }

        try {
            assertEquals(
                EventOfferResult.ACCEPTED,
                forwarder.send(
                    "in-flight",
                    required = true,
                    coalesceKey = "loaded:in-flight",
                    collapseGroup = "loaded",
                    collapsedEvent = "sync-all",
                ),
            )
            withTimeout(1_000L) { firstStarted.await() }
            repeat(1_000) { index ->
                val startedAt = System.nanoTime()
                val result = forwarder.send(
                    "provider-$index",
                    required = true,
                    coalesceKey = "loaded:provider-$index",
                    collapseGroup = "loaded",
                    collapsedEvent = "sync-all",
                )
                val elapsedMillis = (System.nanoTime() - startedAt) / 1_000_000
                assertTrue("send took ${elapsedMillis}ms", elapsedMillis < 50L)
                assertTrue(result != EventOfferResult.DROPPED && result != EventOfferResult.CLOSED)
                assertTrue(forwarder.pendingCount() <= 4)
            }
            val pending = forwarder.pendingCount()
            releaseFirst.complete(Unit)
            val drained = buildList {
                repeat(pending + 1) {
                    add(withTimeout(1_000L) { delivered.receive() })
                }
            }
            assertEquals("in-flight", drained.first())
            assertTrue("full sync event was not retained: $drained", "sync-all" in drained)
        } finally {
            forwarder.close()
            scope.cancel()
        }
    }

    @Test
    fun mixedRequiredOverflowRetainsProviderSyncAndLatestGeoStates() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val delivered = Channel<String>(8)
        val forwarder = EventForwarder(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 5,
        ) { value: String ->
            if (value == "in-flight") {
                firstStarted.complete(Unit)
                releaseFirst.await()
            }
            delivered.send(value)
        }

        try {
            forwarder.send("in-flight", required = true)
            withTimeout(1_000L) { firstStarted.await() }
            repeat(5) { index ->
                assertEquals(
                    EventOfferResult.ACCEPTED,
                    forwarder.send(
                        "loaded-$index",
                        required = true,
                        coalesceKey = "loaded:$index",
                        collapseGroup = "loaded",
                        collapsedEvent = "sync-all",
                    ),
                )
            }
            val firstGeo = forwarder.send(
                "geo-country",
                required = true,
                coalesceKey = "geoUpdate:country",
            )
            assertTrue(firstGeo != EventOfferResult.DROPPED)
            assertEquals(
                EventOfferResult.ACCEPTED,
                forwarder.send("geo-asn", required = true, coalesceKey = "geoUpdate:asn"),
            )
            assertEquals(
                EventOfferResult.ACCEPTED,
                forwarder.send("geo-ip", required = true, coalesceKey = "geoUpdate:geoip"),
            )
            assertEquals(
                EventOfferResult.ACCEPTED,
                forwarder.send("geo-site", required = true, coalesceKey = "geoUpdate:geosite"),
            )
            val loadedIntoMixed = forwarder.send(
                "loaded-new",
                required = true,
                coalesceKey = "loaded:new",
                collapseGroup = "loaded",
                collapsedEvent = "sync-all",
            )
            assertTrue(loadedIntoMixed != EventOfferResult.DROPPED)
            assertTrue(forwarder.pendingCount() <= 5)

            val pending = forwarder.pendingCount()
            releaseFirst.complete(Unit)
            val drained = buildList {
                repeat(pending + 1) {
                    add(withTimeout(1_000L) { delivered.receive() })
                }
            }
            assertTrue("sync-all" in drained)
            assertTrue("geo-country" in drained)
            assertTrue("geo-asn" in drained)
            assertTrue("geo-ip" in drained)
            assertTrue("geo-site" in drained)
        } finally {
            forwarder.close()
            scope.cancel()
        }
    }

    @Test
    fun singleDeliveryFailureDoesNotSilenceLaterEvents() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val delivered = CompletableDeferred<Int>()
        val errors = Channel<Throwable>(1)
        val forwarder = EventForwarder<Int>(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 2,
            onConsumeError = { errors.trySend(it) },
        ) { value ->
            if (value == 1) error("injected delivery failure")
            delivered.complete(value)
        }

        try {
            assertEquals(EventOfferResult.ACCEPTED, forwarder.send(1, required = true))
            withTimeout(1_000L) { errors.receive() }
            assertEquals(EventOfferResult.ACCEPTED, forwarder.send(2, required = true))
            assertEquals(2, withTimeout(1_000L) { delivered.await() })
        } finally {
            forwarder.close()
            scope.cancel()
        }
    }

    @Test
    fun listenerReplacementRejectsOldGeneration() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val oldStarted = CompletableDeferred<Unit>()
        val oldForwarder = EventForwarder<Int>(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 1,
        ) {
            oldStarted.complete(Unit)
            awaitCancellation()
        }

        try {
            assertEquals(EventOfferResult.ACCEPTED, oldForwarder.send(1, required = true))
            withTimeout(1_000L) { oldStarted.await() }
            generation.incrementAndGet()
            oldForwarder.close()
            withTimeout(1_000L) { oldForwarder.join() }
            assertEquals(EventOfferResult.CLOSED, oldForwarder.send(2, required = true))
        } finally {
            oldForwarder.close()
            scope.cancel()
        }
    }

    @Test
    fun closeCancelsInFlightEventDelivery() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val generation = AtomicLong(1L)
        val started = CompletableDeferred<Unit>()
        val cancelled = CompletableDeferred<Unit>()
        val forwarder = EventForwarder<Int>(
            generation = 1L,
            activeGeneration = generation,
            scope = scope,
            capacity = 1,
        ) {
            try {
                started.complete(Unit)
                awaitCancellation()
            } finally {
                cancelled.complete(Unit)
            }
        }

        assertEquals(EventOfferResult.ACCEPTED, forwarder.send(1, required = true))
        withTimeout(1_000L) { started.await() }
        forwarder.close()
        withTimeout(1_000L) {
            forwarder.join()
            cancelled.await()
        }
        scope.cancel()
    }

    @Test
    fun coreEventRequirementMarkerIsExplicit() {
        assertTrue(isRequiredCoreEvent("{\"eventRequired\":true}"))
        assertFalse(isRequiredCoreEvent("{\"data\":{\"type\":\"log\"}}"))
        assertEquals(
            CoreEventQueueMetadata(required = true, type = "loaded", key = "provider"),
            coreEventQueueMetadata(
                "{\"eventRequired\":true,\"eventType\":\"loaded\",\"eventKey\":\"provider\"}",
            ),
        )
    }
}
