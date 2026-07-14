package com.follow.clash.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteServiceLifecycleTest {
    @Test
    fun lateCleanupOnlyOwnsTheDelegateItCaptured() {
        val destroyedDelegate = Any()
        val replacementDelegate = Any()

        assertTrue(ownsServiceState(destroyedDelegate, destroyedDelegate))
        assertFalse(ownsServiceState(replacementDelegate, destroyedDelegate))
    }
}
