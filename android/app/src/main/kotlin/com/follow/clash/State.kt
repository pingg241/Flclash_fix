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

enum class RunState {
    START, PENDING, STOP
}


object State {

    val runLock = Mutex()

    var runTime: Long = 0

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

    suspend fun handleSyncState() {
        runLock.withLock {
            try {
                Service.bind()
                runTime = Service.getRunTime()
                val runState = when (runTime == 0L) {
                    true -> RunState.STOP
                    false -> RunState.START
                }
                runStateFlow.tryEmit(runState)
            } catch (_: Exception) {
                runStateFlow.tryEmit(RunState.STOP)
            }
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
        val options: VpnOptions = runLock.withLock {
            if (runStateFlow.value == RunState.START) {
                return true
            }
            if (runStateFlow.value == RunState.PENDING) {
                return false
            }
            val opts = sharedState.vpnOptions ?: return false
            runStateFlow.tryEmit(RunState.PENDING)
            opts
        }
        try {
            val appPlugin = this.appPlugin
            if (appPlugin != null) {
                val granted = suspendCancellableCoroutine { cont ->
                    appPlugin.prepareAwait(options.enable) { ok ->
                        if (cont.isActive) cont.resume(ok)
                    }
                }
                if (!granted) {
                    runLock.withLock { runStateFlow.tryEmit(RunState.STOP) }
                    return false
                }
                val time = Service.startService(options, runTime)
                return runLock.withLock {
                    // startService completes without throw => session started
                    // (runTime may stay 0 on some paths; still treat as running).
                    runTime = if (time != 0L) time else System.currentTimeMillis()
                    runStateFlow.tryEmit(RunState.START)
                    true
                }
            }
            val intent = VpnService.prepare(GlobalState.application)
            if (intent != null) {
                runLock.withLock { runStateFlow.tryEmit(RunState.STOP) }
                return false
            }
            val time = Service.startService(options, runTime)
            return runLock.withLock {
                runTime = if (time != 0L) time else System.currentTimeMillis()
                runStateFlow.tryEmit(RunState.START)
                true
            }
        } catch (_: Exception) {
            runLock.withLock { runStateFlow.tryEmit(RunState.STOP) }
            return false
        } finally {
            runLock.withLock {
                if (runStateFlow.value == RunState.PENDING) {
                    runStateFlow.tryEmit(RunState.STOP)
                }
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
        GlobalState.setCrashlytics(sharedState.crashlytics)
        Service.updateNotificationParams(
            NotificationParams(
                title = sharedState.currentProfileName,
                stopText = sharedState.stopText,
                onlyStatisticsProxy = sharedState.onlyStatisticsProxy
            )
        )
        Service.setCrashlytics(sharedState.crashlytics)
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
            runLock.withLock {
                if (runStateFlow.value != RunState.STOP) {
                    return@launch
                }
                try {
                    runStateFlow.tryEmit(RunState.PENDING)
                    val options = sharedState.vpnOptions ?: return@launch
                    appPlugin?.let {
                        it.prepare(options.enable) {
                            runTime = Service.startService(options, runTime)
                            runStateFlow.tryEmit(RunState.START)
                        }
                    } ?: run {
                        val intent = VpnService.prepare(GlobalState.application)
                        if (intent != null) {
                            return@launch
                        }
                        runTime = Service.startService(options, runTime)
                        runStateFlow.tryEmit(RunState.START)
                    }
                } finally {
                    if (runStateFlow.value == RunState.PENDING) {
                        runStateFlow.tryEmit(RunState.STOP)
                    }
                }
            }
        }
    }

    fun handleStopService() {
        GlobalState.launch {
            runLock.withLock {
                if (runStateFlow.value != RunState.START) {
                    return@launch
                }
                try {
                    runStateFlow.tryEmit(RunState.PENDING)
                    runTime = Service.stopService()
                    runStateFlow.tryEmit(RunState.STOP)
                } finally {
                    if (runStateFlow.value == RunState.PENDING) {
                        runStateFlow.tryEmit(RunState.START)
                    }
                }
            }
        }
    }
}



