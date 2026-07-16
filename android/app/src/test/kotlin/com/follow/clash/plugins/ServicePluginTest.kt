package com.follow.clash.plugins

import com.follow.clash.synchronizeServiceState
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class ServicePluginTest {
    @Test
    fun invokeFailureCompletesMethodCall() = runBlocking {
        var result: String? = null
        var failure: Throwable? = null
        val expected = IllegalStateException("binder unavailable")

        completeInvokeAction(
            data = "{}",
            invoke = { _, _ -> Result.failure(expected) },
            onResult = { result = it },
            onFailure = { failure = it },
        )

        assertNull(result)
        assertEquals(expected, failure)
    }

    @Test
    fun runtimeSyncTimeoutCompletesMethodCallWithFailure() = runBlocking<Unit> {
        var result: Long? = null
        var failure: Throwable? = null

        completeServiceCall(
            operation = {
                withTimeout(10) {
                    delay(100)
                    1L
                }
            },
            onResult = { result = it },
            onFailure = { failure = it },
        )

        assertNull(result)
        assertIs<TimeoutCancellationException>(failure)
    }

    @Test
    fun notificationFailureCompletesStateSyncWithOneError() = runBlocking {
        val expected = IllegalStateException("notification update failed")
        var notificationCalls = 0
        var crashlyticsCalls = 0
        var successCount = 0
        val failures = mutableListOf<Throwable>()

        completeServiceCall(
            operation = {
                synchronizeServiceState(
                    updateNotificationParams = {
                        notificationCalls++
                        Result.failure(expected)
                    },
                    setCrashlytics = {
                        crashlyticsCalls++
                        Result.success(Unit)
                    },
                )
            },
            onResult = { successCount++ },
            onFailure = failures::add,
        )

        assertEquals(1, notificationCalls)
        assertEquals(0, crashlyticsCalls)
        assertEquals(0, successCount)
        assertEquals(listOf<Throwable>(expected), failures)
    }

    @Test
    fun crashlyticsFailureCompletesStateSyncWithOneError() = runBlocking {
        val expected = IllegalStateException("crashlytics update failed")
        var notificationCalls = 0
        var crashlyticsCalls = 0
        var successCount = 0
        val failures = mutableListOf<Throwable>()

        completeServiceCall(
            operation = {
                synchronizeServiceState(
                    updateNotificationParams = {
                        notificationCalls++
                        Result.success(Unit)
                    },
                    setCrashlytics = {
                        crashlyticsCalls++
                        Result.failure(expected)
                    },
                )
            },
            onResult = { successCount++ },
            onFailure = failures::add,
        )

        assertEquals(1, notificationCalls)
        assertEquals(1, crashlyticsCalls)
        assertEquals(0, successCount)
        assertEquals(listOf<Throwable>(expected), failures)
    }
}
