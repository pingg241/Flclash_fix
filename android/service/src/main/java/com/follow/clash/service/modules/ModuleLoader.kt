package com.follow.clash.service.modules

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface ModuleLoaderScope {
    fun <T : Module> install(module: T): T
}

interface ModuleLoader {
    suspend fun load()

    suspend fun cancel()
}

fun CoroutineScope.moduleLoader(block: suspend ModuleLoaderScope.() -> Unit): ModuleLoader {
    val modules = mutableListOf<Module>()
    val mutex = Mutex()

    return object : ModuleLoader {
        override suspend fun load() {
            withContext(Dispatchers.IO) {
                mutex.withLock {
                    if (modules.isNotEmpty()) return@withLock
                    val scope = object : ModuleLoaderScope {
                        override fun <T : Module> install(module: T): T {
                            module.install()
                            modules.add(module)
                            return module
                        }
                    }
                    try {
                        scope.block()
                    } catch (error: Throwable) {
                        modules.asReversed().forEach { module ->
                            runCatching { module.uninstall() }
                        }
                        modules.clear()
                        throw error
                    }
                }
            }
        }

        override suspend fun cancel() {
            withContext(Dispatchers.IO) {
                mutex.withLock {
                    var failure: Throwable? = null
                    modules.asReversed().forEach { module ->
                        runCatching { module.uninstall() }.onFailure { error ->
                            val currentFailure = failure
                            if (currentFailure == null) {
                                failure = error
                            } else {
                                currentFailure.addSuppressed(error)
                            }
                        }
                    }
                    modules.clear()
                    failure?.let { throw it }
                }
            }
        }
    }
}
