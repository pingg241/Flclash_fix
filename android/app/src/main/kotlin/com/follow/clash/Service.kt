package com.follow.clash

import com.follow.clash.common.GlobalState
import com.follow.clash.common.Components.SERVICE_OPERATION_FAILED
import com.follow.clash.common.ServiceDelegate
import com.follow.clash.common.formatString
import com.follow.clash.common.intent
import com.follow.clash.service.IAckInterface
import com.follow.clash.service.ICallbackInterface
import com.follow.clash.service.IEventInterface
import com.follow.clash.service.IRemoteInterface
import com.follow.clash.service.IResultInterface
import com.follow.clash.service.IVoidInterface
import com.follow.clash.service.RemoteService
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object Service {
    private val delegate by lazy {
        ServiceDelegate<IRemoteInterface>(
            RemoteService::class.intent, ::handleServiceDisconnected
        ) {
            IRemoteInterface.Stub.asInterface(it)
        }
    }

    var onServiceDisconnected: ((String) -> Unit)? = null

    private fun handleServiceDisconnected(message: String) {
        onServiceDisconnected?.let {
            it(message)
        }
    }

    fun bind() {
        delegate.bind()
    }

    fun unbind() {
        delegate.unbind()
    }

    suspend fun invokeAction(data: String, cb: ((result: String) -> Unit)?): Result<Unit> {
        val res = mutableListOf<ByteArray>()
        return delegate.useService {
            it.invokeAction(
                data, object : ICallbackInterface.Stub() {
                    override fun onResult(
                        result: ByteArray?, isSuccess: Boolean, ack: IAckInterface?
                    ) {
                        res.add(result ?: byteArrayOf())
                        ack?.onAck()
                        if (isSuccess) {
                            cb?.let { cb ->
                                cb(res.formatString())
                            }
                        }
                    }
                })
        }
    }

    suspend fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        onStarted: (() -> Unit)?,
        onResult: ((result: String) -> Unit)?,
    ): Result<Unit> {
        val res = mutableListOf<ByteArray>()
        return delegate.useService {
            it.quickSetup(
                initParamsString,
                setupParamsString,
                object : ICallbackInterface.Stub() {
                    override fun onResult(
                        result: ByteArray?, isSuccess: Boolean, ack: IAckInterface?
                    ) {
                        res.add(result ?: byteArrayOf())
                        ack?.onAck()
                        if (isSuccess) {
                            onResult?.let { cb ->
                                cb(res.formatString())
                            }
                        }
                    }
                },
                object : IVoidInterface.Stub() {
                    override fun invoke() {
                        onStarted?.let { onStarted ->
                            onStarted()
                        }
                    }
                }
            )
        }
    }

    suspend fun setEventListener(
        cb: ((result: String?) -> Unit)?
    ): Result<Unit> {
        val results = HashMap<String, MutableList<ByteArray>>()
        return delegate.useService {
            it.setEventListener(
                when (cb != null) {
                    true -> object : IEventInterface.Stub() {
                        override fun onEvent(
                            id: String, data: ByteArray?, isSuccess: Boolean, ack: IAckInterface?
                        ) {
                            if (results[id] == null) {
                                results[id] = mutableListOf()
                            }
                            results[id]?.add(data ?: byteArrayOf())
                            ack?.onAck()
                            if (isSuccess) {
                                cb(results[id]?.formatString())
                                results.remove(id)
                            }
                        }
                    }

                    false -> null
                })
        }
    }

    suspend fun updateNotificationParams(
        params: NotificationParams
    ): Result<Unit> {
        return delegate.useService {
            it.updateNotificationParams(params)
        }
    }

    suspend fun setCrashlytics(
        enable: Boolean
    ): Result<Unit> {
        return delegate.useService {
            it.setCrashlytics(enable)
        }
    }

    private suspend fun awaitIResultInterface(
        block: (IResultInterface) -> Unit
    ): Long = suspendCancellableCoroutine { continuation ->
        val callback = object : IResultInterface.Stub() {
            override fun onResult(time: Long) {
                if (!continuation.isActive) {
                    return
                }
                if (time == SERVICE_OPERATION_FAILED) {
                    continuation.resumeWithException(
                        IllegalStateException("Remote service operation failed")
                    )
                } else {
                    continuation.resume(time)
                }
            }
        }

        try {
            block(callback)
        } catch (e: Exception) {
            GlobalState.log("awaitIResultInterface $e")
            if (continuation.isActive) {
                continuation.resumeWithException(e)
            }
        }
    }


    suspend fun startService(
        operationId: String,
        options: VpnOptions,
        runTime: Long,
    ): Long {
        return delegate.useService(OPERATION_TIMEOUT_MILLIS) {
            awaitIResultInterface { callback ->
                it.startService(operationId, options, runTime, callback)
            }
        }.getOrThrow()
    }

    suspend fun cancelStart(operationId: String): Long {
        return delegate.useService(OPERATION_TIMEOUT_MILLIS) {
            awaitIResultInterface { callback ->
                it.cancelStart(operationId, callback)
            }
        }.getOrThrow()
    }

    suspend fun stopService(): Long {
        return delegate.useService(OPERATION_TIMEOUT_MILLIS) {
            awaitIResultInterface { callback ->
                it.stopService(callback)
            }
        }.getOrThrow()
    }

    suspend fun getRunTime(): Long {
        return delegate.useService {
            it.runTime
        }.getOrThrow()
    }

    private const val OPERATION_TIMEOUT_MILLIS = 20_000L
}
