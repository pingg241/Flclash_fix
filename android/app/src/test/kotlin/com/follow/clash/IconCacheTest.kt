package com.follow.clash

import java.io.File
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class IconCacheTest {
    @Test
    fun samePackageLoadsOnlyOnceConcurrently() = runBlocking {
        val loads = AtomicInteger()
        val singleFlight = KeyedSingleFlight<String, String>()

        val results = coroutineScope {
            List(16) {
                async {
                    singleFlight.run("package") {
                        loads.incrementAndGet()
                        delay(20)
                        "icon"
                    }
                }
            }.awaitAll()
        }

        assertEquals(1, loads.get())
        assertTrue(results.all { it == "icon" })
    }

    @Test
    fun failedIconLoadCanRetry() = runBlocking {
        val loads = AtomicInteger()
        val singleFlight = KeyedSingleFlight<String, String>()

        assertTrue(
            runCatching {
                singleFlight.run("package") {
                    loads.incrementAndGet()
                    error("encode failed")
                }
            }.isFailure,
        )
        assertEquals(
            "icon",
            singleFlight.run("package") {
                loads.incrementAndGet()
                "icon"
            },
        )
        assertEquals(2, loads.get())
    }

    @Test
    fun cleanupRemovesTemporaryExpiredAndLeastRecentlyUsedFiles() {
        val root = Files.createTempDirectory("flclash-icons-").toFile()
        try {
            val now = 10_000L
            val preserve = root.resolve("preserve.webp").apply {
                writeText("preserve")
                setLastModified(1L)
            }
            val temporary = root.resolve("icon.webp.tmp-1").apply { writeText("temp") }
            val expired = root.resolve("expired.webp").apply {
                writeText("expired")
                setLastModified(1L)
            }
            val recent = root.resolve("recent.webp").apply {
                writeText("recent")
                setLastModified(9_000L)
            }
            val older = root.resolve("older.webp").apply {
                writeText("older")
                setLastModified(8_000L)
            }

            pruneIconCache(
                root,
                setOf(preserve.absolutePath),
                now,
                ttlMillis = 5_000L,
                maxFiles = 2,
            )

            assertTrue(preserve.exists())
            assertTrue(recent.exists())
            assertFalse(older.exists())
            assertFalse(expired.exists())
            assertFalse(temporary.exists())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun concurrentPublishedPathsSurviveInterleavedCleanup() = runBlocking {
        val root = Files.createTempDirectory("flclash-icons-concurrent-").toFile()
        try {
            val coordinator = IconCacheCoordinator()
            val published = AtomicInteger()
            val cleaned = AtomicInteger()
            val allPublished = CompletableDeferred<Unit>()
            val allCleaned = CompletableDeferred<Unit>()

            val results = coroutineScope {
                listOf("first.webp", "second.webp").map { name ->
                    async {
                        val file = root.resolve(name)
                        coordinator.withActivePath(file) {
                            file.writeText(name)
                            if (published.incrementAndGet() == 2) {
                                allPublished.complete(Unit)
                            }
                            allPublished.await()
                            coordinator.cleanup { activePaths ->
                                pruneIconCache(
                                    root,
                                    activePaths,
                                    now = System.currentTimeMillis(),
                                    ttlMillis = Long.MAX_VALUE,
                                    maxFiles = 1,
                                )
                            }
                            if (cleaned.incrementAndGet() == 2) {
                                allCleaned.complete(Unit)
                            }
                            allCleaned.await()
                            file.absolutePath
                        }
                    }
                }.awaitAll()
            }

            assertTrue(results.all { File(it).exists() })
        } finally {
            root.deleteRecursively()
        }
    }
}
