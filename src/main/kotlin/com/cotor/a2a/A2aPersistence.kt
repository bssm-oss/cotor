package com.cotor.a2a

import com.cotor.storage.writeTextAtomically
import java.nio.file.Path

internal fun writeA2aTextAtomically(path: Path, payload: String) {
    writeTextAtomically(path, payload)
}
