package com.follow.clash

import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class RuntimeStateTest {
    @Test
    fun syncTimeoutDoesNotCommitStoppedState() = runBlocking {
        val initial = RuntimeSnapshot(
            runTime = 42L,
            runningOperationId = "existing",
            runState = RunState.START,
        )
        var committed = initial

        val failure = runCatching {
            synchronizeRuntimeState(
                current = initial,
                fetchRunTime = {
                    withTimeout(10) {
                        delay(100)
                        0L
                    }
                },
                commit = { committed = it },
            )
        }.exceptionOrNull()

        assertIs<TimeoutCancellationException>(failure)
        assertEquals(initial, committed)
    }

    @Test
    fun successfulZeroRuntimeCommitsStoppedState() = runBlocking {
        var committed: RuntimeSnapshot? = null

        val runTime = synchronizeRuntimeState(
            current = RuntimeSnapshot(
                runTime = 42L,
                runningOperationId = "existing",
                runState = RunState.START,
            ),
            fetchRunTime = { 0L },
            commit = { committed = it },
        )

        assertEquals(0L, runTime)
        assertEquals(
            RuntimeSnapshot(
                runTime = 0L,
                runningOperationId = null,
                runState = RunState.STOP,
            ),
            committed,
        )
    }

    @Test
    fun successfulRunningSyncPreservesRuntimeOwner() = runBlocking {
        var committed: RuntimeSnapshot? = null

        synchronizeRuntimeState(
            current = RuntimeSnapshot(
                runTime = 42L,
                runningOperationId = "existing",
                runState = RunState.START,
            ),
            fetchRunTime = { 84L },
            commit = { committed = it },
        )

        assertEquals(
            RuntimeSnapshot(
                runTime = 84L,
                runningOperationId = "existing",
                runState = RunState.START,
            ),
            committed,
        )
    }

    @Test
    fun pendingSyncDoesNotCommitRuntimeState() = runBlocking {
        val initial = RuntimeSnapshot(
            runTime = 42L,
            runningOperationId = "existing",
            runState = RunState.PENDING,
        )
        var committed = initial

        val runTime = synchronizeRuntimeState(
            current = initial,
            fetchRunTime = { 0L },
            commit = { committed = it },
        )

        assertEquals(0L, runTime)
        assertEquals(initial, committed)
    }

    @Test
    fun onlyPendingOwnerCanRestoreStartSnapshot() {
        assertEquals(
            true,
            canRestorePendingStart(RunState.PENDING, "current", "current"),
        )
        assertEquals(
            false,
            canRestorePendingStart(RunState.PENDING, "current", "stale"),
        )
        assertEquals(
            false,
            canRestorePendingStart(RunState.START, "current", "current"),
        )
    }
}
