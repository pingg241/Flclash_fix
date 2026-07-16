package com.follow.clash.service

import org.junit.Assert.assertEquals
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

    @Test
    fun stoppedRuntimeStartsNewService() {
        val resolution = resolveExistingRuntimeStart(runTime = 0L)

        assertEquals(ExistingRuntimeAction.START_NEW, resolution)
    }

    @Test
    fun existingRuntimeIsRejectedWithoutTransferringOwnership() {
        assertEquals(
            ExistingRuntimeAction.REJECT,
            resolveExistingRuntimeStart(runTime = 42L),
        )
        assertTrue(ownsStartOperation("existing", "existing"))
        assertFalse(ownsStartOperation("existing", "new"))
    }
}
