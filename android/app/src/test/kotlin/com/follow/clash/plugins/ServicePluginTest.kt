package com.follow.clash.plugins

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
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
}
