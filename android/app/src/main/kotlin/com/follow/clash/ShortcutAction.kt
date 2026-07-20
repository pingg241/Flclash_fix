package com.follow.clash

import android.content.Context
import android.content.Intent
import android.util.Base64
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.follow.clash.common.Components
import com.follow.clash.common.QuickAction
import com.follow.clash.common.action
import com.follow.clash.common.intent
import java.security.MessageDigest
import java.security.SecureRandom

object ShortcutAction {
    private const val SHORTCUT_ID = "toggle"
    private const val PREFERENCES_NAME = "shortcut_actions"
    private const val TOKEN_KEY = "toggle_token"
    private const val TOKEN_EXTRA = "com.pingg241.flclash.extra.SHORTCUT_TOKEN"
    private const val TOKEN_SIZE = 32

    fun publishToggle(context: Context, label: CharSequence) {
        val token = ByteArray(TOKEN_SIZE).also(SecureRandom()::nextBytes)
        val encodedToken = Base64.encodeToString(token, Base64.NO_WRAP or Base64.URL_SAFE)
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(TOKEN_KEY, encodedToken)
            .apply()
        val intent = Components.MAIN_ACTIVITY.intent.apply {
            action = QuickAction.TOGGLE.action
            putExtra(TOKEN_EXTRA, encodedToken)
        }
        val shortcut = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel(label)
            .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher_round))
            .setIntent(intent)
            .build()
        ShortcutManagerCompat.setDynamicShortcuts(context, listOf(shortcut))
    }

    fun consumeIfAuthorized(context: Context, intent: Intent?): Boolean {
        if (intent?.action != QuickAction.TOGGLE.action) return false
        val suppliedToken = intent.getStringExtra(TOKEN_EXTRA) ?: return false
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val expectedToken = preferences.getString(TOKEN_KEY, null) ?: return false
        if (!tokensEqual(suppliedToken, expectedToken)) return false
        preferences.edit().remove(TOKEN_KEY).apply()
        intent.removeExtra(TOKEN_EXTRA)
        val label = ShortcutManagerCompat.getDynamicShortcuts(context)
            .firstOrNull { it.id == SHORTCUT_ID }
            ?.shortLabel
            ?: context.applicationInfo.loadLabel(context.packageManager)
        runCatching { publishToggle(context, label) }
        return true
    }

    internal fun tokensEqual(suppliedToken: String, expectedToken: String): Boolean {
        return MessageDigest.isEqual(
            suppliedToken.toByteArray(Charsets.UTF_8),
            expectedToken.toByteArray(Charsets.UTF_8),
        )
    }
}
