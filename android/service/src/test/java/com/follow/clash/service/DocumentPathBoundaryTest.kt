package com.follow.clash.service

import java.io.File
import java.io.IOException
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DocumentPathBoundaryTest {
    @Test
    fun rootDocumentIdResolvesToOwnedRoot() {
        withTempDirectory { root ->
            assertEquals(root.canonicalFile, DocumentPathBoundary.resolve(root, "/"))
        }
    }

    @Test
    fun relativeDocumentIdRoundTrips() {
        withTempDirectory { root ->
            val child = File(root, "profiles/config.yaml").apply {
                requireNotNull(parentFile).mkdirs()
                writeText("test")
            }

            val documentId = DocumentPathBoundary.documentId(root, child)

            assertEquals("/profiles/config.yaml", documentId)
            assertEquals(child.canonicalFile, DocumentPathBoundary.resolve(root, documentId))
        }
    }

    @Test
    fun traversalAndMalformedIdsAreRejected() {
        withTempDirectory { root ->
            listOf("profiles/config.yaml", "/../secret", "/profiles/../secret", "/profiles/a/b.yaml", "/profiles/C:secret.yaml")
                .forEach { documentId ->
                    assertFailsWith<IOException>(documentId) {
                        DocumentPathBoundary.resolve(root, documentId)
                    }
                }
        }
    }

    @Test
    fun sensitiveInternalFilesAndProviderCacheAreRejected() {
        withTempDirectory { root ->
            listOf(
                "/database.sqlite",
                "/shared_preferences.json",
                "/backup.zip",
                "/config.yaml",
                "/profiles/providers",
                "/profiles/providers/cache.yaml",
                "/scripts/token.txt",
            ).forEach { documentId ->
                assertFailsWith<IOException>(documentId) {
                    DocumentPathBoundary.resolve(root, documentId)
                }
            }
        }
    }

    @Test
    fun childrenIncludeOnlyAllowlistedRegularFiles() {
        withTempDirectory { root ->
            val profiles = File(root, "profiles").apply { mkdirs() }
            val yaml = File(profiles, "visible.yaml").apply { writeText("test") }
            File(profiles, "secret.txt").writeText("secret")
            File(profiles, "providers").apply { mkdirs() }

            val children = DocumentPathBoundary.children(root, "/profiles", profiles)

            assertEquals(listOf(yaml.canonicalFile), children.map(File::getCanonicalFile))
        }
    }

    @Test
    fun siblingWithMatchingPrefixIsRejected() {
        withTempDirectory { parent ->
            val root = File(parent, "data").apply { mkdirs() }
            val sibling = File(parent, "data-backup/config.yaml").apply {
                requireNotNull(parentFile).mkdirs()
                writeText("test")
            }

            assertFailsWith<IOException> {
                DocumentPathBoundary.documentId(root, sibling)
            }
        }
    }

    @Test
    fun symlinkLeavingRootIsRejectedWhenSupported() {
        if (System.getProperty("os.name")?.startsWith("Windows") == true) return
        withTempDirectory { parent ->
            val root = File(parent, "data").apply { mkdirs() }
            val profiles = File(root, "profiles").apply { mkdirs() }
            val outside = File(parent, "outside.yaml").apply { writeText("secret") }
            val link = File(profiles, "escaped.yaml").toPath()
            try {
                Files.createSymbolicLink(link, outside.toPath())
            } catch (_: UnsupportedOperationException) {
                return@withTempDirectory
            } catch (_: IOException) {
                return@withTempDirectory
            } catch (_: SecurityException) {
                return@withTempDirectory
            }

            assertFailsWith<IOException> {
                DocumentPathBoundary.resolve(root, "/profiles/escaped.yaml")
            }
        }
    }

    private fun withTempDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("flclash-documents-").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}
