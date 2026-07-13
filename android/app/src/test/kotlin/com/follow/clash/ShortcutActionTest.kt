package com.follow.clash

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ShortcutActionTest {
    @Test
    fun tokenComparisonRejectsForgedAndTruncatedValues() {
        val token = "valid-high-entropy-token"

        assertTrue(ShortcutAction.tokensEqual(token, token))
        assertFalse(ShortcutAction.tokensEqual("forged-token", token))
        assertFalse(ShortcutAction.tokensEqual(token.dropLast(1), token))
    }
}
