package com.follow.clash.common

import android.content.ComponentName

object Components {
    const val PACKAGE_NAME = "com.pingg241.flclash"
    private const val IMPLEMENTATION_PACKAGE = "com.follow.clash"
    const val SERVICE_OPERATION_FAILED = Long.MIN_VALUE

    val MAIN_ACTIVITY =
        ComponentName(GlobalState.packageName, "${IMPLEMENTATION_PACKAGE}.MainActivity")

    val TEMP_ACTIVITY =
        ComponentName(GlobalState.packageName, "${IMPLEMENTATION_PACKAGE}.TempActivity")

    val BROADCAST_RECEIVER =
        ComponentName(GlobalState.packageName, "${IMPLEMENTATION_PACKAGE}.BroadcastReceiver")
}
