package com.follow.clash

import android.app.Application
import android.content.Context.MODE_PRIVATE
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.widget.Toast
import androidx.core.graphics.drawable.toBitmap
import com.follow.clash.common.GlobalState
import com.follow.clash.models.SharedState
import com.google.gson.Gson
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

private const val ICON_TTL_DAYS = 1L
private const val MAX_ICON_CACHE_FILES = 256
private const val ICON_FILE_SUFFIX = ".webp"
private const val ICON_TEMP_MARKER = ".tmp-"

private val packageIconLoads = KeyedSingleFlight<String, String>()
private val defaultIconMutex = Mutex()
private val iconCacheCoordinator = IconCacheCoordinator()
private val iconCleanupRunning = AtomicBoolean(false)

val Application.sharedState: SharedState
    get() {
        try {
            val sp = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val res = sp.getString("flutter.sharedState", "")
            return Gson().fromJson(res, SharedState::class.java)
        } catch (_: Exception) {
            return SharedState()
        }
    }


private var lastToast: Toast? = null

fun Application.showToast(text: String?) {
    Handler(Looper.getMainLooper()).post {
        lastToast?.cancel()
        lastToast = Toast.makeText(this, text, Toast.LENGTH_LONG).apply {
            show()
        }
    }

}

suspend fun PackageManager.getPackageIconPath(packageName: String): String =
    packageIconLoads.run(packageName) {
        withContext(Dispatchers.IO) {
            val iconDir = File(GlobalState.application.cacheDir, "icons").apply {
                check(exists() || mkdirs()) { "Failed to create icon cache directory" }
            }
            val result = try {
                loadPackageIcon(packageName, iconDir)
            } catch (_: Exception) {
                loadDefaultIcon(iconDir)
            }
            result
        }
    }

private suspend fun PackageManager.loadPackageIcon(
    packageName: String,
    iconDir: File,
): String {
    val lastUpdateTime = getPackageInfo(packageName, 0).lastUpdateTime
    val packageKey = packageName.sha256()
    val iconFile = File(iconDir, "${packageKey}_$lastUpdateTime$ICON_FILE_SUFFIX")
    return iconCacheCoordinator.withActivePath(iconFile) {
        if (iconFile.isCompleteIcon() && !isExpired(iconFile)) {
            iconFile.setLastModified(System.currentTimeMillis())
        } else {
            iconDir.listFiles { file ->
                file.name.startsWith("${packageKey}_") && file.name.endsWith(ICON_FILE_SUFFIX)
            }?.forEach { stale ->
                if (stale != iconFile) stale.delete()
            }
            saveDrawableAtomically(getApplicationIcon(packageName), iconFile)
        }

        cleanupIconCache(iconDir)
        iconFile.absolutePath
    }
}

private suspend fun PackageManager.loadDefaultIcon(iconDir: File): String =
    defaultIconMutex.withLock {
        val defaultIconFile = File(iconDir, "default_icon$ICON_FILE_SUFFIX")
        iconCacheCoordinator.withActivePath(defaultIconFile) {
            if (!defaultIconFile.isCompleteIcon()) {
                saveDrawableAtomically(defaultActivityIcon, defaultIconFile)
            }
            defaultIconFile.setLastModified(System.currentTimeMillis())
            cleanupIconCache(iconDir)
            defaultIconFile.absolutePath
        }
    }

private suspend fun saveDrawableAtomically(drawable: Drawable, file: File) {
    val bitmap = withContext(Dispatchers.Default) {
        drawable.toBitmap(width = 128, height = 128)
    }
    val temporary = File(file.parentFile, "${file.name}$ICON_TEMP_MARKER${System.nanoTime()}")
    try {
        val format = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                Bitmap.CompressFormat.WEBP_LOSSY
            }

            else -> {
                Bitmap.CompressFormat.WEBP
            }
        }
        FileOutputStream(temporary).use { output ->
            check(bitmap.compress(format, 90, output)) { "Failed to encode package icon" }
            output.fd.sync()
        }
        check(temporary.isCompleteIcon()) { "Encoded package icon is empty" }
        Os.rename(temporary.path, file.path)
    } finally {
        temporary.delete()
        if (!bitmap.isRecycled) bitmap.recycle()
    }
}

private fun isExpired(file: File): Boolean {
    val now = System.currentTimeMillis()
    val age = now - file.lastModified()
    return age > TimeUnit.DAYS.toMillis(ICON_TTL_DAYS)
}

private fun File.isCompleteIcon(): Boolean = isFile && length() > 0L

private fun String.sha256(): String {
    return MessageDigest.getInstance("SHA-256")
        .digest(toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}

private suspend fun cleanupIconCache(iconDir: File) {
    if (!iconCleanupRunning.compareAndSet(false, true)) return
    try {
        iconCacheCoordinator.cleanup { activePaths ->
            pruneIconCache(
                iconDir = iconDir,
                preservePaths = activePaths,
                now = System.currentTimeMillis(),
                ttlMillis = TimeUnit.DAYS.toMillis(ICON_TTL_DAYS),
                maxFiles = MAX_ICON_CACHE_FILES,
            )
        }
    } finally {
        iconCleanupRunning.set(false)
    }
}

internal fun pruneIconCache(
    iconDir: File,
    preservePaths: Set<String>,
    now: Long,
    ttlMillis: Long,
    maxFiles: Int,
) {
    val candidates = iconDir.listFiles()
        ?.asSequence()
        ?.filter(File::isFile)
        ?.filter { it.absolutePath !in preservePaths }
        ?.toList()
        .orEmpty()
    candidates.filter { it.name.contains(ICON_TEMP_MARKER) }.forEach(File::delete)
    val icons = candidates
        .asSequence()
        .filter { it.name.endsWith(ICON_FILE_SUFFIX) && it.name != "default_icon$ICON_FILE_SUFFIX" }
        .filter { file ->
            val expired = now - file.lastModified() > ttlMillis
            if (expired) file.delete()
            !expired
        }
        .sortedByDescending(File::lastModified)
        .toList()
    icons.drop((maxFiles - 1).coerceAtLeast(0)).forEach(File::delete)
}

internal class IconCacheCoordinator {
    private val mutex = Mutex()
    private val activePaths = mutableSetOf<String>()

    suspend fun <T> withActivePath(file: File, operation: suspend () -> T): T {
        val path = file.absolutePath
        mutex.withLock { activePaths.add(path) }
        try {
            return operation()
        } finally {
            mutex.withLock { activePaths.remove(path) }
        }
    }

    suspend fun cleanup(operation: (Set<String>) -> Unit) {
        mutex.withLock { operation(activePaths.toSet()) }
    }
}

internal class KeyedSingleFlight<K : Any, V : Any> {
    private val inFlight = ConcurrentHashMap<K, CompletableDeferred<V>>()

    suspend fun run(key: K, operation: suspend () -> V): V {
        val candidate = CompletableDeferred<V>()
        val shared = inFlight.putIfAbsent(key, candidate)
        if (shared != null) return shared.await()
        try {
            return operation().also(candidate::complete)
        } catch (error: Throwable) {
            candidate.completeExceptionally(error)
            throw error
        } finally {
            inFlight.remove(key, candidate)
        }
    }
}

suspend fun <T> MethodChannel.awaitResult(
    method: String, arguments: Any? = null
): T? = withContext(Dispatchers.Main) {
    suspendCancellableCoroutine { continuation ->
        invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) {
                @Suppress("UNCHECKED_CAST") continuation.resume(result as T?)
            }

            override fun error(code: String, message: String?, details: Any?) {
                continuation.resume(null)
            }

            override fun notImplemented() {
                continuation.resume(null)
            }
        })
    }
}

inline fun <reified T : FlutterPlugin> FlutterEngine.plugin(): T? {
    return plugins.get(T::class.java) as T?
}

fun <T> MethodChannel.invokeMethodOnMainThread(
    method: String, arguments: Any? = null, callback: ((Result<T>) -> Unit)? = null
) {
    Handler(Looper.getMainLooper()).post {
        invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) {
                @Suppress("UNCHECKED_CAST") callback?.invoke(Result.success(result as T))
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                val exception = Exception("MethodChannel error: $errorCode - $errorMessage")
                callback?.invoke(Result.failure(exception))
            }

            override fun notImplemented() {
                val exception = NotImplementedError("Method not implemented: $method")
                callback?.invoke(Result.failure(exception))
            }
        })
    }
}
