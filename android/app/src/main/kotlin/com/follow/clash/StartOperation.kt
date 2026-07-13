package com.follow.clash

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withTimeoutOrNull

internal const val START_OPERATION_CANCELLATION_TIMEOUT_MILLIS = 25_000L

internal suspend fun awaitStartOperationCompletion(
    operation: StartOperation,
    timeoutMillis: Long = START_OPERATION_CANCELLATION_TIMEOUT_MILLIS,
): Boolean {
    return withTimeoutOrNull(timeoutMillis) {
        operation.completed.await()
        true
    } ?: false
}

internal class StartOperationCancelledException(id: String) :
    CancellationException("Start operation $id was cancelled")

internal class StartOperation(
    val id: String,
    val generation: Long,
) {
    val completed = CompletableDeferred<Unit>()

    @Volatile
    var ownsRuntime = false
        private set

    @Volatile
    var isCancelled = false
        private set

    private var isDispatched = false

    @Synchronized
    fun cancel(): Boolean {
        isCancelled = true
        return isDispatched || ownsRuntime
    }

    @Synchronized
    fun tryDispatch(): Boolean {
        if (isCancelled) {
            return false
        }
        isDispatched = true
        return true
    }

    @Synchronized
    fun commitRuntime(block: () -> Unit): Boolean {
        if (isCancelled) {
            return false
        }
        block()
        ownsRuntime = true
        return true
    }

    fun ensureActive() {
        if (isCancelled) {
            throw StartOperationCancelledException(id)
        }
    }
}

internal data class StartTransition(
    val operation: StartOperation,
    val previous: StartOperation?,
)

internal class StartOperationCoordinator {
    private var generation = 0L
    private var current: StartOperation? = null
    private val operations = mutableMapOf<String, StartOperation>()

    @Synchronized
    fun begin(id: String): StartTransition {
        require(id.isNotBlank()) { "Start operation ID must not be blank" }
        check(operations[id] == null) { "Duplicate start operation ID" }
        val previous = current?.also { it.cancel() }
        val operation = StartOperation(id, ++generation)
        operations[id] = operation
        current = operation
        return StartTransition(operation, previous)
    }

    @Synchronized
    fun cancel(id: String): StartOperation? {
        return operations[id]?.also { it.cancel() }
    }

    @Synchronized
    fun cancelCurrent(): StartOperation? {
        return current?.also { it.cancel() }
    }

    @Synchronized
    fun finish(operation: StartOperation) {
        if (current === operation) {
            current = null
        }
        operation.completed.complete(Unit)
    }

    @Synchronized
    fun forget(operation: StartOperation) {
        if (current !== operation) {
            operations.remove(operation.id, operation)
        }
    }
}

internal object StartOperations {
    val coordinator = StartOperationCoordinator()
}
