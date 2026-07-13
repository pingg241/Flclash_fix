package com.follow.clash.service

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

class FilesProvider : DocumentsProvider() {

    companion object {
        private const val DEFAULT_ROOT_ID = "0"

        private val DEFAULT_DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        private val DEFAULT_ROOT_COLUMNS = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_SUMMARY,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID
        )
    }

    override fun onCreate(): Boolean {
        return true
    }

    override fun queryRoots(projection: Array<String>?): Cursor {
        return MatrixCursor(projection ?: DEFAULT_ROOT_COLUMNS).apply {
            newRow().apply {
                add(DocumentsContract.Root.COLUMN_ROOT_ID, DEFAULT_ROOT_ID)
                add(DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.FLAG_LOCAL_ONLY)
                add(DocumentsContract.Root.COLUMN_ICON, R.drawable.ic_service)
                add(DocumentsContract.Root.COLUMN_TITLE, "FlClash")
                add(DocumentsContract.Root.COLUMN_SUMMARY, "Data")
                add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, "/")
            }
        }
    }


    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<String>?,
        sortOrder: String?
    ): Cursor {
        val result = MatrixCursor(resolveDocumentProjection(projection))
        if (parentDocumentId == "/") {
            DocumentPathBoundary.roots(filesDir()).forEach { root ->
                includeFile(result, root.directory, root.documentId, isVirtualDirectory = true)
            }
            return result
        }
        val parentFile = resolveFile(parentDocumentId)
        DocumentPathBoundary.children(filesDir(), parentDocumentId, parentFile).forEach { file ->
            includeFile(result, file, DocumentPathBoundary.documentId(filesDir(), file))
        }
        return result
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val result = MatrixCursor(resolveDocumentProjection(projection))
        val file = resolveFile(documentId)
        val isVirtualDirectory = DocumentPathBoundary.isExportRoot(documentId)
        if (!isVirtualDirectory && !file.exists()) {
            throw FileNotFoundException("Document not found")
        }
        includeFile(result, file, documentId, isVirtualDirectory)
        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val file = resolveFile(documentId)
        if (!file.isFile) {
            throw FileNotFoundException("Document not found")
        }
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    private fun includeFile(
        result: MatrixCursor,
        file: File,
        documentId: String,
        isVirtualDirectory: Boolean = false,
    ) {
        val isDirectory = isVirtualDirectory || file.isDirectory
        val flags = if (!isDirectory && file.isFile) {
            DocumentsContract.Document.FLAG_SUPPORTS_WRITE
        } else {
            0
        }
        result.newRow().apply {
            add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, documentId)
            add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, file.name)
            add(DocumentsContract.Document.COLUMN_SIZE, file.length())
            add(
                DocumentsContract.Document.COLUMN_FLAGS,
                flags
            )
            add(DocumentsContract.Document.COLUMN_MIME_TYPE, getDocumentType(isDirectory))
        }
    }

    private fun getDocumentType(isDirectory: Boolean): String {
        return if (isDirectory) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            "application/octet-stream"
        }
    }

    private fun resolveDocumentProjection(projection: Array<String>?): Array<String> {
        return projection ?: DEFAULT_DOCUMENT_COLUMNS
    }

    private fun resolveFile(documentId: String): File {
        return try {
            DocumentPathBoundary.resolve(filesDir(), documentId)
        } catch (error: IOException) {
            throw FileNotFoundException(error.message)
        }
    }

    private fun filesDir(): File {
        return context?.filesDir ?: throw FileNotFoundException("Data directory not found")
    }
}

internal object DocumentPathBoundary {
    private const val ROOT_DOCUMENT_ID = "/"
    private val ALLOWED_ROOTS = listOf(
        AllowedRoot("profiles", setOf("yaml", "yml")),
        AllowedRoot("scripts", setOf("js")),
    )

    data class ResolvedRoot(
        val documentId: String,
        val directory: File,
    )

    private data class AllowedRoot(
        val name: String,
        val extensions: Set<String>,
    )

    fun roots(filesDir: File): List<ResolvedRoot> {
        return ALLOWED_ROOTS.map { root ->
            ResolvedRoot("/${root.name}", File(filesDir, root.name))
        }
    }

    fun isExportRoot(documentId: String): Boolean {
        return ALLOWED_ROOTS.any { documentId == "/${it.name}" }
    }

    @Throws(IOException::class)
    fun resolve(root: File, documentId: String): File {
        val canonicalRoot = root.canonicalFile
        if (documentId == ROOT_DOCUMENT_ID) return canonicalRoot
        if (!documentId.startsWith(ROOT_DOCUMENT_ID) || documentId.indexOf('\u0000') >= 0) {
            throw IOException("Invalid document ID")
        }
        val segments = documentId.removePrefix(ROOT_DOCUMENT_ID).split('/')
        val allowedRoot = ALLOWED_ROOTS.firstOrNull { it.name == segments.firstOrNull() }
            ?: throw IOException("Document root is not exported")
        if (segments.size !in 1..2 ||
            segments.any { it.isEmpty() || it == "." || it == ".." || it.contains(':') }
        ) {
            throw IOException("Invalid document ID")
        }
        if (segments.size == 2 && segments[1].substringAfterLast('.', "").lowercase() !in allowedRoot.extensions) {
            throw IOException("File type is not exported")
        }
        val candidate = File(canonicalRoot, segments.joinToString(File.separator)).canonicalFile
        ensureWithinRoot(canonicalRoot, candidate)
        return candidate
    }

    @Throws(IOException::class)
    fun documentId(root: File, file: File): String {
        val canonicalRoot = root.canonicalFile
        val canonicalFile = file.canonicalFile
        ensureWithinRoot(canonicalRoot, canonicalFile)
        val relativePath = canonicalFile.relativeTo(canonicalRoot).invariantSeparatorsPath
        val segments = relativePath.split('/')
        val allowedRoot = ALLOWED_ROOTS.firstOrNull { it.name == segments.firstOrNull() }
            ?: throw IOException("Document root is not exported")
        if (segments.size == 1) return "/${allowedRoot.name}"
        if (segments.size != 2 ||
            segments[1].substringAfterLast('.', "").lowercase() !in allowedRoot.extensions
        ) {
            throw IOException("Document is not exported")
        }
        return "/$relativePath"
    }

    @Throws(IOException::class)
    fun children(root: File, documentId: String, directory: File): List<File> {
        if (documentId == ROOT_DOCUMENT_ID || !directory.isDirectory) {
            throw IOException("Parent directory not found")
        }
        return directory.listFiles()
            ?.asSequence()
            ?.filter { it.isFile }
            ?.filter { runCatching { documentId(root, it) }.isSuccess }
            ?.toList()
            ?: emptyList()
    }

    @Throws(IOException::class)
    private fun ensureWithinRoot(root: File, file: File) {
        val rootPath = root.toPath()
        if (!file.toPath().startsWith(rootPath)) {
            throw IOException("Document is outside the data directory")
        }
    }
}
