package com.follow.clash.plugins

import com.follow.clash.Service
import com.follow.clash.StartOperation
import com.follow.clash.StartOperationCancelledException
import com.follow.clash.StartOperations
import com.follow.clash.State
import com.follow.clash.awaitStartOperationCompletion
import com.follow.clash.common.Components
import com.follow.clash.invokeMethodOnMainThread
import com.follow.clash.models.SharedState
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.concurrent.atomic.AtomicBoolean

private class OnceResult(private val delegate: MethodChannel.Result) {
    private val completed = AtomicBoolean(false)

    fun success(value: Any?) {
        if (completed.compareAndSet(false, true)) {
            delegate.success(value)
        }
    }

    fun error(code: String, message: String?) {
        if (completed.compareAndSet(false, true)) {
            delegate.error(code, message, null)
        }
    }
}

class ServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {
    private lateinit var flutterMethodChannel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        flutterMethodChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger, "${Components.PACKAGE_NAME}/service"
        )
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        flutterMethodChannel.setMethodCallHandler(null)
        Service.onServiceDisconnected = null
        cancelCurrentStartWithoutWaiting()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) = when (call.method) {
        "init" -> {
            handleInit(result)
        }

        "shutdown" -> {
            handleShutdown(result)
        }

        "invokeAction" -> {
            handleInvokeAction(call, result)
        }

        "getRunTime" -> {
            handleGetRunTime(result)
        }

        "syncState" -> {
            handleSyncState(call, result)
        }

        "start" -> {
            handleStart(call, result)
        }

        "cancelStart" -> {
            handleCancelStart(call, result)
        }

        "stop" -> {
            handleStop(result)
        }

        else -> {
            result.notImplemented()
        }
    }

    private fun handleInvokeAction(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments<String>()
        if (data == null) {
            result.error("invalid_action", "Missing core action payload", null)
            return
        }
        val reply = OnceResult(result)
        launch {
            completeInvokeAction(
                data = data,
                invoke = Service::invokeAction,
                onResult = reply::success,
                onFailure = { error ->
                    reply.error("invoke_failed", error.message)
                },
            )
        }
    }

    private fun handleShutdown(result: MethodChannel.Result) {
        launch {
            val cancelled = StartOperations.coordinator.cancelCurrent()?.let {
                cancelStartOperation(it)
            } ?: true
            if (cancelled) {
                Service.unbind()
            }
            result.success(cancelled)
        }
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val operationId = call.argument<String>("operationId")
        if (operationId.isNullOrBlank()) {
            result.error("invalid_start", "Missing start operation ID", null)
            return
        }
        val transition = runCatching {
            StartOperations.coordinator.begin(operationId)
        }.getOrElse { error ->
            result.error("invalid_start", error.message, null)
            return
        }
        val operation = transition.operation
        val reply = OnceResult(result)
        launch {
            try {
                transition.previous?.let { cancelStartOperation(it) }
                operation.ensureActive()
                reply.success(State.startServiceAndAwait(operation))
            } catch (error: StartOperationCancelledException) {
                reply.error("start_cancelled", error.message)
            } catch (error: Exception) {
                reply.error("start_failed", error.message)
            } finally {
                StartOperations.coordinator.finish(operation)
                launch {
                    delay(COMPLETED_OPERATION_RETENTION_MILLIS)
                    StartOperations.coordinator.forget(operation)
                }
            }
        }
    }

    private fun handleCancelStart(call: MethodCall, result: MethodChannel.Result) {
        val operationId = call.argument<String>("operationId")
        if (operationId.isNullOrBlank()) {
            result.error("invalid_cancel", "Missing start operation ID", null)
            return
        }
        val operation = StartOperations.coordinator.cancel(operationId)
        if (operation == null) {
            result.success(false)
            return
        }
        val reply = OnceResult(result)
        launch {
            val cancelled = cancelStartOperation(operation)
            StartOperations.coordinator.forget(operation)
            reply.success(cancelled)
        }
    }

    private suspend fun cancelStartOperation(operation: StartOperation): Boolean = coroutineScope {
        val requiresRemoteCancellation = operation.cancel()
        State.appPlugin?.cancelVpnPrepare(operation.id)
        val remoteCancellation = async {
            if (requiresRemoteCancellation) {
                runCatching {
                    Service.cancelStart(operation.id) == 0L
                }.getOrDefault(false)
            } else {
                true
            }
        }
        val completed = awaitStartOperationCompletion(operation)
        val remoteCancelled = remoteCancellation.await()
        if (remoteCancelled && operation.ownsRuntime) {
            State.handleCancelledStart(operation.id)
        }
        remoteCancelled && completed
    }

    private fun cancelCurrentStartWithoutWaiting() {
        val operation = StartOperations.coordinator.cancelCurrent() ?: return
        State.appPlugin?.cancelVpnPrepare(operation.id)
        if (operation.cancel()) {
            launch {
                val cancelled = runCatching {
                    Service.cancelStart(operation.id) == 0L
                }.getOrDefault(false)
                if (cancelled && operation.ownsRuntime) {
                    State.handleCancelledStart(operation.id)
                }
            }
        }
    }

    private fun handleStop(result: MethodChannel.Result) {
        launch {
            try {
                val cancelled = StartOperations.coordinator.cancelCurrent()?.let {
                    cancelStartOperation(it)
                } ?: true
                result.success(State.stopServiceAndAwait() && cancelled)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }

    val semaphore = Semaphore(10)

    fun handleSendEvent(value: String?) {
        launch(Dispatchers.Main) {
            semaphore.withPermit {
                flutterMethodChannel.invokeMethod("event", value)
            }
        }
    }

    private fun onServiceDisconnected(message: String) {
        launch {
            State.handleServiceDisconnected()
        }
        flutterMethodChannel.invokeMethodOnMainThread<Any>("crash", message)
    }

    private fun handleSyncState(call: MethodCall, result: MethodChannel.Result) {
        val reply = OnceResult(result)
        launch {
            completeServiceCall(
                operation = {
                    val data = call.arguments<String>()
                        ?: throw IllegalArgumentException("Missing shared state")
                    State.sharedState = Gson().fromJson(data, SharedState::class.java)
                    State.syncState()
                    ""
                },
                onResult = reply::success,
                onFailure = { error ->
                    reply.error("state_sync_failed", error.message)
                },
            )
        }
    }


    fun handleInit(result: MethodChannel.Result) {
        Service.bind()
        launch {
            Service.setEventListener {
                handleSendEvent(it)
            }.onSuccess {
                result.success("")
            }.onFailure {
                result.success(it.message)
            }

        }
        Service.onServiceDisconnected = ::onServiceDisconnected
    }

    private fun handleGetRunTime(result: MethodChannel.Result) {
        val reply = OnceResult(result)
        launch {
            completeServiceCall(
                operation = State::handleSyncState,
                onResult = reply::success,
                onFailure = { error ->
                    reply.error("runtime_sync_failed", error.message)
                },
            )
        }
    }

    companion object {
        private const val COMPLETED_OPERATION_RETENTION_MILLIS = 60_000L
    }
}

internal suspend fun completeInvokeAction(
    data: String,
    invoke: suspend (String, ((String) -> Unit)?) -> Result<Unit>,
    onResult: (String) -> Unit,
    onFailure: (Throwable) -> Unit,
) {
    try {
        invoke(data, onResult).onFailure(onFailure)
    } catch (error: Exception) {
        onFailure(error)
    }
}

internal suspend fun <T> completeServiceCall(
    operation: suspend () -> T,
    onResult: (T) -> Unit,
    onFailure: (Throwable) -> Unit,
) {
    try {
        onResult(operation())
    } catch (error: Exception) {
        onFailure(error)
    }
}
