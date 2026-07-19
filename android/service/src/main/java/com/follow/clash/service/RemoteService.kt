package com.follow.clash.service

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.follow.clash.common.GlobalState
import com.follow.clash.common.ServiceDelegate
import com.follow.clash.common.chunkedForAidl
import com.follow.clash.common.intent
import com.follow.clash.common.Components.SERVICE_OPERATION_FAILED
import com.follow.clash.core.Core
import com.follow.clash.service.State.delegate
import com.follow.clash.service.State.intent
import com.follow.clash.service.State.runLock
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import com.google.gson.JsonParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume

internal enum class ExistingRuntimeAction {
    START_NEW,
    REJECT,
}

internal fun resolveExistingRuntimeStart(
    runTime: Long,
): ExistingRuntimeAction = if (runTime > 0L) {
    ExistingRuntimeAction.REJECT
} else {
    ExistingRuntimeAction.START_NEW
}

internal fun ownsStartOperation(ownerOperationId: String?, operationId: String): Boolean =
    ownerOperationId == operationId

class RemoteService : Service(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {
    private val cancelledStartOperations = ConcurrentHashMap.newKeySet<String>()
    private val pendingStartOperations = ConcurrentHashMap.newKeySet<String>()
    private val eventListenerInstallLock = Any()
    private val eventListenerGeneration = AtomicLong()
    private val droppedEvents = AtomicLong()
    private var eventForwarder: EventForwarder<String>? = null

    private suspend fun stopActiveServiceLocked() {
        val activeDelegate = delegate
        if (activeDelegate == null) {
            clearServiceState()
            return
        }
        activeDelegate.useService(STOP_TIMEOUT_MILLIS) { service ->
            service.stop()
        }.getOrThrow()
        activeDelegate.unbind()
        if (delegate === activeDelegate) {
            clearServiceState()
        }
    }

    private fun handleStopService(result: IResultInterface) {
        launch {
            val response = runCatching {
                runLock.withLock {
                    stopActiveServiceLocked()
                    0L
                }
            }.getOrElse { error ->
                GlobalState.log("Stop background service failed: $error")
                SERVICE_OPERATION_FAILED
            }
            respond(result, response)
        }
    }

    private fun clearServiceState() {
        intent = null
        delegate = null
        State.options = null
        State.runTime = 0L
        State.startOperationId = null
    }

    private fun handleServiceDisconnected(
        disconnectedDelegate: ServiceDelegate<IBaseService>,
        message: String,
    ) {
        GlobalState.log("Background service disconnected: $message")
        launch {
            runLock.withLock {
                if (delegate === disconnectedDelegate) {
                    clearServiceState()
                }
            }
        }
    }

    private fun handleStartService(
        operationId: String,
        options: VpnOptions,
        requestedRunTime: Long,
        result: IResultInterface,
    ) {
        launch {
            try {
                val response = runCatching {
                    runLock.withLock {
                        check(!cancelledStartOperations.contains(operationId)) {
                            "Start operation was cancelled"
                        }
                        val existingRuntime = resolveExistingRuntimeStart(
                            runTime = State.runTime,
                        )
                        when (existingRuntime) {
                            ExistingRuntimeAction.REJECT -> {
                                error("Background service is already running")
                            }

                            ExistingRuntimeAction.START_NEW -> Unit
                        }
                        val nextIntent = when (options.enable) {
                            true -> VpnService::class.intent
                            false -> CommonService::class.intent
                        }
                        if (intent?.component != nextIntent.component || delegate == null) {
                            delegate?.unbind()
                            lateinit var nextDelegate: ServiceDelegate<IBaseService>
                            nextDelegate = ServiceDelegate(
                                nextIntent,
                                { message -> handleServiceDisconnected(nextDelegate, message) },
                            ) { binder ->
                                when (binder) {
                                    is VpnService.LocalBinder -> binder.getService()
                                    is CommonService.LocalBinder -> binder.getService()
                                    else -> throw IllegalArgumentException("Invalid binder type")
                                }
                            }
                            delegate = nextDelegate
                            intent = nextIntent
                            nextDelegate.bind()
                        }
                        val activeDelegate = checkNotNull(delegate)
                        State.options = options
                        try {
                            activeDelegate.useService(START_TIMEOUT_MILLIS) { service ->
                                service.start()
                            }.getOrThrow()
                            if (cancelledStartOperations.contains(operationId)) {
                                stopActiveServiceLocked()
                                error("Start operation was cancelled")
                            }
                        } catch (error: Exception) {
                            activeDelegate.unbind()
                            if (delegate === activeDelegate) {
                                clearServiceState()
                            }
                            throw error
                        }
                        State.runTime = requestedRunTime.takeIf { it > 0L }
                            ?: System.currentTimeMillis()
                        State.startOperationId = operationId
                        State.runTime
                    }
                }.getOrElse { error ->
                    GlobalState.log("Start background service failed: $error")
                    SERVICE_OPERATION_FAILED
                }
                respond(result, response)
            } finally {
                pendingStartOperations.remove(operationId)
                cancelledStartOperations.remove(operationId)
            }
        }
    }

    private fun handleCancelStart(operationId: String, result: IResultInterface) {
        cancelledStartOperations.add(operationId)
        launch {
            val response = runCatching {
                runLock.withLock {
                    if (ownsStartOperation(State.startOperationId, operationId)) {
                        stopActiveServiceLocked()
                    }
                    0L
                }
            }.getOrElse { error ->
                GlobalState.log("Cancel background service start failed: $error")
                SERVICE_OPERATION_FAILED
            }
            respond(result, response)
            if (!pendingStartOperations.contains(operationId)) {
                cancelledStartOperations.remove(operationId)
            }
        }
    }

    private fun respond(result: IResultInterface, response: Long) {
        runCatching {
            result.onResult(response)
        }.onFailure { error ->
            GlobalState.log("Send service result failed: $error")
        }
    }

    private suspend fun awaitAck(send: (IAckInterface) -> Unit) {
        withTimeout(ACK_TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                send(
                    object : IAckInterface.Stub() {
                        override fun onAck() {
                            if (continuation.isActive) {
                                continuation.resume(Unit)
                            }
                        }
                    },
                )
            }
        }
    }

    private suspend fun deliverEvent(
        eventListener: IEventInterface,
        generation: Long,
        value: String,
    ) {
        val id = UUID.randomUUID().toString()
        val chunks = value.chunkedForAidl()
        for ((index, chunk) in chunks.withIndex()) {
            if (eventListenerGeneration.get() != generation) return
            awaitAck { ack ->
                eventListener.onEvent(
                    id,
                    chunk,
                    index == chunks.lastIndex,
                    ack,
                )
            }
        }
    }

    private fun replaceEventListener(eventListener: IEventInterface?) {
        synchronized(eventListenerInstallLock) {
            val generation = eventListenerGeneration.incrementAndGet()
            eventForwarder?.close()
            eventForwarder = null
            droppedEvents.set(0L)
            if (eventListener == null) {
                Core.callSetEventListener(null)
                return
            }

            val forwarder = EventForwarder<String>(
                generation = generation,
                activeGeneration = eventListenerGeneration,
                scope = this,
                capacity = EVENT_QUEUE_CAPACITY,
                onConsumeError = { error ->
                    GlobalState.log("Forward core event failed: $error")
                },
            ) { value ->
                deliverEvent(eventListener, generation, value)
            }
            eventForwarder = forwarder
            Core.callSetEventListener { value ->
                if (value == null) return@callSetEventListener
                val metadata = coreEventQueueMetadata(value)
                val collapseGroup = metadata.type.takeIf { it == LOADED_EVENT_TYPE }
                val coalesceKey = metadata.key?.let { "${metadata.type}:$it" }
                when (
                    forwarder.send(
                        event = value,
                        required = metadata.required,
                        coalesceKey = coalesceKey,
                        collapseGroup = collapseGroup,
                        collapsedEvent = PROVIDER_SYNC_EVENT.takeIf { collapseGroup != null },
                    )
                ) {
                    EventOfferResult.ACCEPTED,
                    EventOfferResult.COALESCED,
                    EventOfferResult.CLOSED -> Unit

                    EventOfferResult.ACCEPTED_AFTER_EVICTION,
                    EventOfferResult.DROPPED -> {
                        val dropped = droppedEvents.incrementAndGet()
                        if (dropped == 1L || dropped % 100L == 0L) {
                            GlobalState.log("Core event queue full; dropped $dropped events")
                        }
                    }
                }
            }
        }
    }

    private val binder = object : IRemoteInterface.Stub() {
        override fun invokeAction(data: String, callback: ICallbackInterface) {
            Core.invokeAction(data) {
                launch {
                    runCatching {
                        val chunks = it.orEmpty().chunkedForAidl()
                        for ((index, chunk) in chunks.withIndex()) {
                            awaitAck { ack ->
                                callback.onResult(
                                    chunk,
                                    index == chunks.lastIndex,
                                    ack,
                                )
                            }
                        }
                    }
                }
            }
        }

        override fun quickSetup(
            initParamsString: String,
            setupParamsString: String,
            callback: ICallbackInterface,
            onStarted: IVoidInterface
        ) {
            Core.quickSetup(initParamsString, setupParamsString) {
                launch {
                    runCatching {
                        val result = it.orEmpty()
                        val chunks = result.chunkedForAidl()
                        for ((index, chunk) in chunks.withIndex()) {
                            awaitAck { ack ->
                                callback.onResult(
                                    chunk,
                                    index == chunks.lastIndex,
                                    ack,
                                )
                            }
                        }
                        if (quickSetupSucceeded(result)) {
                            onStarted()
                        }
                    }.onFailure { error ->
                        GlobalState.log("Complete quick setup failed: $error")
                    }
                }
            }
        }

        override fun updateNotificationParams(params: NotificationParams?) {
            State.notificationParamsFlow.tryEmit(params)
        }


        override fun startService(
            operationId: String,
            options: VpnOptions,
            runtime: Long,
            result: IResultInterface,
        ) {
            GlobalState.log("remote startService")
            pendingStartOperations.add(operationId)
            handleStartService(operationId, options, runtime, result)
        }

        override fun cancelStart(operationId: String, result: IResultInterface) {
            handleCancelStart(operationId, result)
        }

        override fun stopService(result: IResultInterface) {
            handleStopService(result)
        }

        override fun setEventListener(eventListener: IEventInterface?) {
            GlobalState.log("RemoveEventListener ${eventListener == null}")
            replaceEventListener(eventListener)
        }

        override fun setCrashlytics(enable: Boolean) {
            GlobalState.setCrashlytics(enable)
        }

        override fun getRunTime(): Long {
            return State.runTime
        }
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        GlobalState.log("Remote service destroy")
        val destroyedDelegate = delegate
        runCatching { replaceEventListener(null) }.onFailure { error ->
            GlobalState.log("Remove core event listener failed: $error")
        }
        cancel()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                runLock.withLock {
                    destroyedDelegate?.unbind()
                    if (ownsServiceState(delegate, destroyedDelegate)) {
                        clearServiceState()
                    }
                }
            } finally {
                cancel()
            }
        }
        super.onDestroy()
    }

    companion object {
        private const val ACK_TIMEOUT_MILLIS = 5_000L
        private const val EVENT_QUEUE_CAPACITY = 64
        private const val LOADED_EVENT_TYPE = "loaded"
        private const val PROVIDER_SYNC_EVENT =
            "{\"id\":\"\",\"method\":\"message\",\"data\":{" +
                "\"type\":\"loaded\",\"data\":\"__flclash_sync_all_providers__\"}," +
                "\"code\":0,\"eventRequired\":true,\"eventType\":\"loaded\"," +
                "\"eventKey\":\"__flclash_sync_all_providers__\"}"
        private const val START_TIMEOUT_MILLIS = 15_000L
        private const val STOP_TIMEOUT_MILLIS = 10_000L
    }
}

internal fun ownsServiceState(current: Any?, owner: Any?): Boolean = current === owner

internal fun quickSetupSucceeded(result: String?): Boolean = result.isNullOrEmpty()

internal fun coreEventQueueMetadata(value: String): CoreEventQueueMetadata {
    if (!isRequiredCoreEvent(value)) {
        return CoreEventQueueMetadata(required = false, type = null, key = null)
    }
    return runCatching {
        val root = JsonParser.parseString(value).asJsonObject
        CoreEventQueueMetadata(
            required = true,
            type = root.get("eventType")?.asString,
            key = root.get("eventKey")?.asString,
        )
    }.getOrElse {
        CoreEventQueueMetadata(required = true, type = null, key = null)
    }
}
