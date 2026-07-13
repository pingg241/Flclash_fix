package com.follow.clash.service

import android.content.Intent
import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import android.util.Log
import androidx.core.content.getSystemService
import com.follow.clash.common.AccessControlMode
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import com.follow.clash.service.models.VpnOptions
import com.follow.clash.service.models.getIpv4RouteAddress
import com.follow.clash.service.models.getIpv6RouteAddress
import com.follow.clash.service.models.toCIDR
import com.follow.clash.service.modules.NetworkObserveModule
import com.follow.clash.service.modules.NotificationModule
import com.follow.clash.service.modules.SuspendModule
import com.follow.clash.service.modules.moduleLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.net.InetSocketAddress
import android.net.VpnService as SystemVpnService

class VpnService : SystemVpnService(), IBaseService,
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {

    private val self: VpnService
        get() = this

    private val loader = moduleLoader {
        install(NetworkObserveModule(self))
        install(NotificationModule(self))
        install(SuspendModule(self))
    }

    override fun onCreate() {
        super.onCreate()
        handleCreate()
    }

    override fun onDestroy() {
        handleDestroy()
        super.onDestroy()
    }

    override fun onRevoke() {
        GlobalState.log("VpnService revoked")
        launch {
            runCatching { stop() }.onFailure { error ->
                GlobalState.log("Revoke VPN cleanup failed: $error")
                Core.stopTun()
                stopSelf()
            }
        }
        super.onRevoke()
    }

    private val connectivity by lazy {
        getSystemService<ConnectivityManager>()
    }
    private val uidPageNameMap = mutableMapOf<Int, String>()

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        if (!uidPageNameMap.containsKey(nextUid)) {
            uidPageNameMap[nextUid] = this.packageManager?.getPackagesForUid(nextUid)?.first() ?: ""
        }
        return uidPageNameMap[nextUid] ?: ""
    }

    val VpnOptions.address
        get(): String = buildString {
            append(IPV4_ADDRESS)
            if (ipv6) {
                append(",")
                append(IPV6_ADDRESS)
            }
        }

    val VpnOptions.dns
        get(): String {
            if (dnsHijacking) {
                return NET_ANY
            }
            return buildString {
                append(DNS)
                if (ipv6) {
                    append(",")
                    append(DNS6)
                }
            }
        }


    override fun onLowMemory() {
        Core.forceGC()
        super.onLowMemory()
    }

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): VpnService = this@VpnService

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            try {
                val isSuccess = super.onTransact(code, data, reply, flags)
                if (!isSuccess) {
                    GlobalState.log("VpnService disconnected")
                    handleDestroy()
                }
                return isSuccess
            } catch (e: RemoteException) {
                GlobalState.log("VpnService onTransact $e")
                return false
            }
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    private fun handleStart(options: VpnOptions) {
        val fd = with(Builder()) {
            val cidr = IPV4_ADDRESS.toCIDR()
            addAddress(cidr.address, cidr.prefixLength)
            Log.d(
                "addAddress", "address: ${cidr.address} prefixLength:${cidr.prefixLength}"
            )
            val routeAddress = options.getIpv4RouteAddress()
            if (routeAddress.isNotEmpty()) {
                try {
                    routeAddress.forEach { i ->
                        Log.d(
                            "addRoute4", "address: ${i.address} prefixLength:${i.prefixLength}"
                        )
                        addRoute(i.address, i.prefixLength)
                    }
                } catch (_: Exception) {
                    addRoute(NET_ANY, 0)
                }
            } else {
                addRoute(NET_ANY, 0)
            }
            var ipv6Ready = false
            if (options.ipv6) {
                try {
                    val cidr6 = IPV6_ADDRESS.toCIDR()
                    Log.d(
                        "addAddress6", "address: ${cidr6.address} prefixLength:${cidr6.prefixLength}"
                    )
                    addAddress(cidr6.address, cidr6.prefixLength)
                    ipv6Ready = true
                } catch (_: Exception) {
                    Log.d(
                        "addAddress6", "IPv6 is not supported."
                    )
                }

                if (ipv6Ready) {
                    try {
                        val routeAddress6 = options.getIpv6RouteAddress()
                        if (routeAddress6.isNotEmpty()) {
                            try {
                                routeAddress6.forEach { i ->
                                    Log.d(
                                        "addRoute6",
                                        "address: ${i.address} prefixLength:${i.prefixLength}"
                                    )
                                    addRoute(i.address, i.prefixLength)
                                }
                            } catch (_: Exception) {
                                addRoute(NET_ANY6, 0)
                            }
                        } else {
                            addRoute(NET_ANY6, 0)
                        }
                    } catch (_: Exception) {
                        Log.d("addRoute6", "IPv6 route setup failed.")
                    }
                }
            }
            addDnsServer(DNS)
            if (options.ipv6 && ipv6Ready) {
                addDnsServer(DNS6)
            }
            setMtu(MTU)
            options.accessControlProps.let { accessControl ->
                if (accessControl.enable) {
                    when (accessControl.mode) {
                        AccessControlMode.ACCEPT_SELECTED -> {
                            (accessControl.acceptList + packageName).forEach {
                                try {
                                    addAllowedApplication(it)
                                } catch (_: Exception) {
                                    GlobalState.log("addAllowedApplication failed: $it")
                                }
                            }
                        }

                        AccessControlMode.REJECT_SELECTED -> {
                            (accessControl.rejectList - packageName).forEach {
                                try {
                                    addDisallowedApplication(it)
                                } catch (_: Exception) {
                                    GlobalState.log("addDisallowedApplication failed: $it")
                                }
                            }
                        }
                    }
                } else {
                    // Keep app traffic off TUN by default (pairs with protect()).
                    try {
                        addDisallowedApplication(packageName)
                    } catch (_: Exception) {
                    }
                }
            }
            setSession("FlClash")
            setBlocking(false)
            if (Build.VERSION.SDK_INT >= 29) {
                setMetered(false)
            }
            if (options.allowBypass) {
                allowBypass()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
                GlobalState.log("Open http proxy")
                setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        "127.0.0.1", options.port, options.bypassDomain
                    )
                )
            }
            establish()?.detachFd()
                ?: throw NullPointerException("Establish VPN rejected by system")
        }
        val started = Core.startTun(
            fd,
            protect = this::protect,
            resolverProcess = this::resolverProcess,
            options.stack,
            options.address,
            options.dns
        )
        check(started) { "Core rejected the VPN interface" }
    }

    override suspend fun start() {
        try {
            loader.load()
            val options = checkNotNull(State.options) { "VPN options are missing" }
            handleStart(options)
        } catch (error: Exception) {
            runCatching {
                Core.stopTun()
                loader.cancel()
            }.onFailure { cleanupError ->
                GlobalState.log("VPN start cleanup failed: $cleanupError")
            }
            stopSelf()
            throw error
        }
    }

    override suspend fun stop() {
        try {
            Core.stopTun()
            loader.cancel()
        } finally {
            stopSelf()
        }
    }

    override fun handleDestroy() {
        Core.stopTun()
        launch {
            runCatching { loader.cancel() }.onFailure { error ->
                GlobalState.log("VPN service cleanup failed: $error")
            }
            this@VpnService.cancel()
        }
        super.handleDestroy()
    }

    companion object {
        private const val MTU = 1500
        private const val IPV4_ADDRESS = "172.19.0.1/30"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
        private const val DNS = "172.19.0.2"
        private const val DNS6 = "fdfe:dcba:9876::2"
        private const val NET_ANY = "0.0.0.0"
        private const val NET_ANY6 = "::"
    }
}
