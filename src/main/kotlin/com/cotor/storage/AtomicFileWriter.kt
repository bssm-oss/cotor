package com.cotor.storage

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import kotlin.io.path.createDirectories

internal fun writeTextAtomically(
    path: Path,
    payload: String,
    configureTempFile: (Path) -> Unit = {},
    onAtomicMoveFallback: (Throwable) -> Unit = {}
) {
    val destination = path.toAbsolutePath().normalize()
    val parent = destination.parent ?: error("Cannot write atomic file without a parent directory: $path")
    parent.createDirectories()
    val tempPrefix = destination.fileName.toString().let { fileName ->
        if (fileName.length >= 3) "$fileName." else "cotor-$fileName."
    }
    val tempFile = Files.createTempFile(parent, tempPrefix, ".tmp")
    try {
        configureTempFile(tempFile)
        Files.writeString(tempFile, payload, StandardCharsets.UTF_8)
        runCatching {
            Files.move(tempFile, destination, ATOMIC_MOVE, REPLACE_EXISTING)
        }.getOrElse {
            onAtomicMoveFallback(it)
            Files.move(tempFile, destination, REPLACE_EXISTING)
        }
    } finally {
        Files.deleteIfExists(tempFile)
    }
}
