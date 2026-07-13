package com.follow.clash.core

import java.net.InetAddress
import java.net.InetSocketAddress

data object Core {
    private external fun startTun(
        fd: Int,
        cb: TunInterface,
        stack: String,
        address: String,
        dns: String,
    ): Boolean

    external fun forceGC(
    )

    external fun updateDNS(
        dns: String,
    )

    private fun parseInetSocketAddress(address: String): InetSocketAddress {
        val host: String
        val port: Int
        if (address.startsWith('[')) {
            val closeBracket = address.indexOf(']')
            require(closeBracket > 0) { "Invalid address: $address" }
            host = address.substring(1, closeBracket)
            require(address.getOrNull(closeBracket + 1) == ':') { "Invalid address: $address" }
            port = address.substring(closeBracket + 2).toInt()
        } else {
            val separator = address.lastIndexOf(':')
            require(separator > 0) { "Invalid address: $address" }
            host = address.substring(0, separator)
            port = address.substring(separator + 1).toInt()
        }
        // Parse host:port without URL; getByName on literal IPs does not perform DNS.
        return InetSocketAddress(InetAddress.getByName(host), port)
    }

    fun startTun(
        fd: Int,
        protect: (Int) -> Boolean,
        resolverProcess: (protocol: Int, source: InetSocketAddress, target: InetSocketAddress, uid: Int) -> String,
        stack: String,
        address: String,
        dns: String,
    ): Boolean {
        return startTun(
            fd,
            object : TunInterface {
                override fun protect(fd: Int): Boolean {
                    return protect(fd)
                }

                override fun resolverProcess(
                    protocol: Int,
                    source: String,
                    target: String,
                    uid: Int
                ): String {
                    return resolverProcess(
                        protocol,
                        parseInetSocketAddress(source),
                        parseInetSocketAddress(target),
                        uid,
                    )
                }
            },
            stack,
            address,
            dns
        )
    }

    external fun suspended(
        suspended: Boolean,
    )

    private external fun invokeAction(
        data: String,
        cb: InvokeInterface
    )

    fun invokeAction(
        data: String,
        cb: (result: String?) -> Unit
    ) {
        invokeAction(
            data,
            object : InvokeInterface {
                override fun onResult(result: String?) {
                    cb(result)
                }
            },
        )
    }

    private external fun setEventListener(cb: InvokeInterface?)

    fun callSetEventListener(
        cb: ((result: String?) -> Unit)?
    ) {
        when (cb != null) {
            true -> setEventListener(
                object : InvokeInterface {
                    override fun onResult(result: String?) {
                        cb(result)
                    }
                },
            )

            false -> setEventListener(null)
        }
    }

    fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        cb: (result: String?) -> Unit,
    ) {
        quickSetup(
            initParamsString,
            setupParamsString,
            object : InvokeInterface {
                override fun onResult(result: String?) {
                    cb(result)
                }
            },
        )
    }

    private external fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        cb: InvokeInterface
    )

    external fun stopTun()

    external fun getTraffic(onlyStatisticsProxy: Boolean): String

    external fun getTotalTraffic(onlyStatisticsProxy: Boolean): String

    init {
        System.loadLibrary("core")
    }
}
