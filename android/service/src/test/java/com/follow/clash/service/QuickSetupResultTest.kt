package com.follow.clash.service

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class QuickSetupResultTest {
    @Test
    fun emptyResultStartsService() {
        assertTrue(quickSetupSucceeded(""))
        assertTrue(quickSetupSucceeded(null))
    }

    @Test
    fun setupFailureDoesNotStartService() {
        assertFalse(quickSetupSucceeded("invalid config"))
    }
}
