package com.follow.clash

import android.net.VpnService
import com.follow.clash.common.GlobalState
import com.follow.clash.models.SharedState
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.TilePlugin
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import com.google.gson.Gson
import io.flutter.embedding.engine.FlutterEngine
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

enum class RunState {
    START, PENDING, STOP
}

internal data class RuntimeSnapshot(
    val runTime: Long,
    val runningOperationId: String?,
    val runState: RunState,
)

internal fun resolveSynchronizedRuntimeState(
    current: RuntimeSnapshot,
    runTime: Long,
): RuntimeSnapshot? {
    if (current.runState == RunState.PENDING) {
        return null
    }
    return RuntimeSnapshot(
        runTime = runTime,
        runningOperationId = current.runningOperationId.takeIf { runTime > 0L },
        runState = if (runTime == 0L) RunState.STOP else RunState.START,
    )
}

internal suspend fun synchronizeRuntimeState(
    current: RuntimeSnapshot,
    fetchRunTime: suspend () -> Long,
    commit: (RuntimeSnapshot) -> Unit,
): Long {
    val runTime = fetchRunTime()
    resolveSynchronizedRuntimeState(current, runTime)?.let(commit)
    return runTime
}

internal suspend fun synchronizeServiceState(
    updateNotificationParams: suspend () -> Result<Unit>,
    setCrashlytics: suspend () -> Result<Unit>,
) {
    updateNotificationParams().getOrThrow()
    setCrashlytics().getOrThrow()
}

internal fun canRestorePendingStart(
    runState: RunState,
    pendingOperationId: String?,
    operationId: String,
): Boolean = runState == RunState.PENDING && pendingOperationId == operationId


object State {

    val runLock = Mutex()

    var runTime: Long = 0

    private var runningOperationId: String? = null

    private var pendingOperationId: String? = null

    var sharedState: SharedState = SharedState()

    val runStateFlow: MutableStateFlow<RunState> = MutableStateFlow(RunState.STOP)

    var flutterEngine: FlutterEngine? = null

    val appPlugin: AppPlugin?
        get() = flutterEngine?.plugin<AppPlugin>()

    val tilePlugin: TilePlugin?
        get() = flutterEngine?.plugin<TilePlugin>()

    suspend fun handleToggleAction() {
        var action: (suspend () -> Unit)?
        runLock.withLock {
            action = when (runStateFlow.value) {
                RunState.PENDING -> null
                RunState.START -> ::handleStopServiceAction
                RunState.STOP -> ::handleStartServiceAction
            }
        }
        action?.invoke()
    }

    suspend fun handleSyncState(): Long = runLock.withLock {
        Service.bind()
        synchronizeRuntimeState(runtimeSnapshot(), Service::getRunTime) { snapshot ->
            restoreRuntimeState(snapshot)
        }
    }

    suspend fun handleStartServiceAction() {
        runLock.withLock {
            if (runStateFlow.value != RunState.STOP) {
                return
            }
            tilePlugin?.handleStart()
            if (flutterEngine != null) {
                return
            }
            startServiceWithPref()
        }

    }

    suspend fun handleStopServiceAction() {
        runLock.withLock {
            if (runStateFlow.value != RunState.START) {
                return
            }
            tilePlugin?.handleStop()
            if (flutterEngine != null) {
                return
            }
            GlobalState.application.showToast(sharedState.stopTip)
            handleStopService()
        }
    }

    fun handleStartService() {
        val appPlugin = flutterEngine?.plugin<AppPlugin>()
        if (appPlugin != null) {
            appPlugin.requestNotificationsPermission {
                startService()
            }
            return
        }
        startService()
    }

    /**
     * Start VPN/service and return whether the session is running.
     * Used by Flutter MethodChannel so UI can roll back on failure.
     * Do not hold [runLock] across the VPN permission dialog.
     */
    suspend fun startServiceAndAwait(): Boolean {
        val transition = StartOperations.coordinator.begin("native-${UUID.randomUUID()}")
        val operation = transition.operation
        transition.previous?.let { previous ->
            appPlugin?.cancelVpnPrepare(previous.id)
            if (previous.cancel()) {
                runCatching { Service.cancelStart(previous.id) }
            }
            if (!awaitStartOperationCompletion(previous)) {
                GlobalState.log(
                    "Previous start operation ${previous.id} did not finish before timeout",
                )
            }
        }
        return try {
            startServiceAndAwait(operation)
        } catch (_: Exception) {
            false
        } finally {
            StartOperations.coordinator.finish(operation)
            StartOperations.coordinator.forget(operation)
        }
    }

    internal suspend fun startServiceAndAwait(operation: StartOperation): Boolean {
        var dispatched = false
        val (options, previousState) = runLock.withLock {
            operation.ensureActive()
            if (runStateFlow.value == RunState.START) {
                return true
            }
            if (runStateFlow.value == RunState.PENDING) {
                return false
            }
            val opts = sharedState.vpnOptions ?: return false
            val snapshot = runtimeSnapshot()
            pendingOperationId = operation.id
            runStateFlow.tryEmit(RunState.PENDING)
            opts to snapshot
        }
        try {
            val appPlugin = this.appPlugin
            if (appPlugin != null) {
                val granted = suspendCancellableCoroutine { cont ->
                    appPlugin.prepareAwait(options.enable, operation.id) { ok ->
                        if (cont.isActive) cont.resume(ok)
                    }
                }
                if (!granted) {
                    operation.ensureActive()
                    runLock.withLock {
                        restorePendingStart(operation.id, previousState)
                    }
                    return false
                }
            } else {
                val intent = VpnService.prepare(GlobalState.application)
                if (intent != null) {
                    runLock.withLock {
                        restorePendingStart(operation.id, previousState)
                    }
                    return false
                }
            }

            operation.ensureActive()
            if (!operation.tryDispatch()) {
                throw StartOperationCancelledException(operation.id)
            }
            dispatched = true
            val time = Service.startService(operation.id, options, runTime)
            operation.ensureActive()
            return runLock.withLock {
                operation.ensureActive()
                check(time > 0L) { "Background service returned an invalid run time" }
                check(
                    canRestorePendingStart(
                        runStateFlow.value,
                        pendingOperationId,
                        operation.id,
                    ),
                ) { "Start operation lost pending state ownership" }
                if (!operation.commitRuntime {
                        runTime = time
                        runningOperationId = operation.id
                        pendingOperationId = null
                        runStateFlow.tryEmit(RunState.START)
                    }
                ) {
                    throw StartOperationCancelledException(operation.id)
                }
                true
            }
        } catch (error: Exception) {
            if (dispatched) {
                runCatching { Service.cancelStart(operation.id) }
            }
            runLock.withLock {
                restorePendingStart(operation.id, previousState)
            }
            if (operation.isCancelled) {
                throw StartOperationCancelledException(operation.id)
            }
            throw error
        } finally {
            runLock.withLock {
                restorePendingStart(operation.id, previousState)
            }
        }
    }

    private fun startServiceWithPref() {
        GlobalState.launch {
            runLock.withLock {
                if (runStateFlow.value != RunState.STOP) {
                    return@launch
                }
                sharedState = GlobalState.application.sharedState
                setupAndStart()
            }
        }
    }

    suspend fun syncState() {
        val state = sharedState
        GlobalState.setCrashlytics(state.crashlytics)
        val notificationParams = NotificationParams(
            title = state.currentProfileName,
            stopText = state.stopText,
            onlyStatisticsProxy = state.onlyStatisticsProxy,
        )
        synchronizeServiceState(
            updateNotificationParams = {
                Service.updateNotificationParams(notificationParams)
            },
            setCrashlytics = {
                Service.setCrashlytics(state.crashlytics)
            },
        )
    }

    private suspend fun setupAndStart() {
        Service.bind()
        syncState()
        GlobalState.application.showToast(sharedState.startTip)
        val initParams = mutableMapOf<String, Any>()
        initParams["home-dir"] = GlobalState.application.filesDir.path
        initParams["version"] = android.os.Build.VERSION.SDK_INT
        val initParamsString = Gson().toJson(initParams)
        val setupParamsString = Gson().toJson(sharedState.setupParams)
        Service.quickSetup(
            initParamsString,
            setupParamsString,
            onStarted = {
                startService()
            },
            onResult = {
                if (it.isNotEmpty()) {
                    GlobalState.application.showToast(it)
                }
            },
        )
    }

    private fun startService() {
        GlobalState.launch {
            startServiceAndAwait()
        }
    }

    suspend fun stopServiceAndAwait(): Boolean {
        val shouldStop = runLock.withLock {
            when (runStateFlow.value) {
                RunState.STOP -> return true
                RunState.PENDING -> return false
                RunState.START -> {
                    pendingOperationId = null
                    runStateFlow.tryEmit(RunState.PENDING)
                    true
                }
            }
        }
        if (!shouldStop) return false
        return try {
            val time = Service.stopService()
            check(time == 0L) { "Background service returned an invalid stop result" }
            runLock.withLock {
                runTime = 0L
                runningOperationId = null
                pendingOperationId = null
                runStateFlow.tryEmit(RunState.STOP)
            }
            true
        } catch (_: Exception) {
            runLock.withLock {
                if (runStateFlow.value == RunState.PENDING) {
                    runStateFlow.tryEmit(RunState.START)
                }
            }
            false
        }
    }

    fun handleStopService() {
        GlobalState.launch {
            stopServiceAndAwait()
        }
    }

    suspend fun handleServiceDisconnected() {
        runLock.withLock {
            runTime = 0L
            runningOperationId = null
            pendingOperationId = null
            runStateFlow.tryEmit(RunState.STOP)
        }
    }

    suspend fun handleCancelledStart(operationId: String) {
        runLock.withLock {
            if (runningOperationId == operationId) {
                runTime = 0L
                runningOperationId = null
                pendingOperationId = null
                runStateFlow.tryEmit(RunState.STOP)
            }
        }
    }

    private fun runtimeSnapshot() = RuntimeSnapshot(
        runTime = runTime,
        runningOperationId = runningOperationId,
        runState = runStateFlow.value,
    )

    private fun restoreRuntimeState(snapshot: RuntimeSnapshot) {
        runTime = snapshot.runTime
        runningOperationId = snapshot.runningOperationId
        pendingOperationId = null
        runStateFlow.tryEmit(snapshot.runState)
    }

    private fun restorePendingStart(operationId: String, snapshot: RuntimeSnapshot) {
        if (
            canRestorePendingStart(
                runStateFlow.value,
                pendingOperationId,
                operationId,
            )
        ) {
            restoreRuntimeState(snapshot)
        }
    }
}



