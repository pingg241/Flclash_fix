package com.follow.clash

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

class StartOperationCoordinatorTest {
    @Test
    fun newStartCancelsPreviousOperation() {
        val coordinator = StartOperationCoordinator()
        val first = coordinator.begin("first").operation

        val transition = coordinator.begin("second")

        assertSame(first, transition.previous)
        assertTrue(first.isCancelled)
        assertFalse(transition.operation.isCancelled)
    }

    @Test
    fun cancellationPreventsDispatchAndRuntimeCommit() {
        val coordinator = StartOperationCoordinator()
        val operation = coordinator.begin("start").operation

        coordinator.cancel("start")

        assertFalse(operation.tryDispatch())
        assertFalse(operation.commitRuntime {})
    }

    @Test
    fun unknownCancellationDoesNotAffectCurrentOperation() {
        val coordinator = StartOperationCoordinator()
        val operation = coordinator.begin("start").operation

        assertNull(coordinator.cancel("other"))
        assertTrue(operation.tryDispatch())
        assertTrue(operation.commitRuntime {})
    }

    @Test
    fun stuckPreviousOperationDoesNotBlockNextStartForever() = runBlocking {
        val coordinator = StartOperationCoordinator()
        val previous = coordinator.begin("first").operation
        val next = coordinator.begin("second").operation

        val completed = withTimeout(250) {
            awaitStartOperationCompletion(previous, timeoutMillis = 25)
        }

        assertFalse(completed)
        assertTrue(previous.isCancelled)
        assertFalse(next.isCancelled)
        assertTrue(next.tryDispatch())
        assertTrue(next.commitRuntime {})
    }

    @Test
    fun latePreviousCompletionDoesNotAffectNextGeneration() = runBlocking {
        val coordinator = StartOperationCoordinator()
        val previous = coordinator.begin("first").operation
        val next = coordinator.begin("second").operation

        assertFalse(awaitStartOperationCompletion(previous, timeoutMillis = 1))
        coordinator.finish(previous)

        assertTrue(awaitStartOperationCompletion(previous, timeoutMillis = 25))
        assertFalse(previous.commitRuntime {})
        assertFalse(next.isCancelled)
        assertTrue(next.tryDispatch())
        assertTrue(next.commitRuntime {})
    }
}
