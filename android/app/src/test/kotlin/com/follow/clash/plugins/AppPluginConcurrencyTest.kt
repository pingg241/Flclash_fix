package com.follow.clash.plugins

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppPluginConcurrencyTest {
    @Test
    fun concurrentPackageRequestsShareOneLoad() = runBlocking {
        val loads = AtomicInteger()
        val cache = SuspendSingleFlightCache {
            loads.incrementAndGet()
            delay(20)
            listOf("one", "two")
        }

        val results = coroutineScope {
            List(16) { async { cache.get() } }.awaitAll()
        }

        assertEquals(1, loads.get())
        assertTrue(results.all { it == listOf("one", "two") })
        assertTrue(results.all { it.distinct().size == it.size })
    }

    @Test
    fun failedPackageLoadCanRetry() = runBlocking {
        val loads = AtomicInteger()
        val cache = SuspendSingleFlightCache {
            if (loads.incrementAndGet() == 1) {
                error("scan failed")
            }
            listOf("recovered")
        }

        assertTrue(runCatching { cache.get() }.isFailure)
        assertEquals(listOf("recovered"), cache.get())
        assertEquals(2, loads.get())
    }

    @Test
    fun activityCommandOnlyReportsActualSuccess() {
        assertFalse(executeWhenAvailable<Any>(null) {})
        assertFalse(executeWhenAvailable(Any()) { error("launch failed") })
        assertTrue(executeWhenAvailable(Any()) {})
    }

    @Test
    fun taskUpdateOnlyReportsAnExecutedCommand() {
        assertFalse(updateMatchingTask(emptyList<Int>(), { true }) {})
        assertFalse(updateMatchingTask(listOf(1), { it == 2 }) {})
        assertFalse(updateMatchingTask(listOf(1), { true }) { error("update failed") })
        assertTrue(updateMatchingTask(listOf(1), { true }) {})
    }
}
