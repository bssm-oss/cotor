package com.cotor.data.http

import java.io.InputStream
import java.io.InputStreamReader
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.time.Duration
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Creates JDK HTTP clients whose helper threads cannot keep CLI/test JVMs alive.
 */
object CotorHttpClients {
    private val counter = AtomicInteger()
    private val clientsByConnectTimeout = ConcurrentHashMap<Duration, HttpClient>()
    private val executor = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "cotor-http-${counter.incrementAndGet()}").apply {
            isDaemon = true
        }
    }
    private val defaultClient: HttpClient by lazy { newBuilder().build() }

    fun newBuilder(): HttpClient.Builder = HttpClient.newBuilder().executor(executor)

    fun newClient(): HttpClient = defaultClient

    fun client(connectTimeout: Duration): HttpClient =
        clientsByConnectTimeout.computeIfAbsent(connectTimeout) {
            newBuilder()
                .connectTimeout(it)
                .build()
        }
}

data class BoundedHttpTextResponse(
    val statusCode: Int,
    val body: String,
    val truncated: Boolean
) {
    fun diagnosticBody(): String =
        if (truncated) {
            "$body\n[cotor truncated HTTP response body after ${body.length} chars]"
        } else {
            body
        }
}

fun HttpClient.sendBoundedText(
    request: HttpRequest,
    bodyLimitChars: Int
): BoundedHttpTextResponse {
    val response = send(request, HttpResponse.BodyHandlers.ofInputStream()) as HttpResponse<*>
    val body = when (val rawBody = response.body()) {
        is InputStream -> rawBody.use { stream ->
            readTextBounded(stream, bodyLimitChars.coerceAtLeast(0))
        }
        is String -> rawBody.toBoundedText(bodyLimitChars.coerceAtLeast(0))
        null -> BoundedText("", truncated = false)
        else -> rawBody.toString().toBoundedText(bodyLimitChars.coerceAtLeast(0))
    }
    return BoundedHttpTextResponse(
        statusCode = response.statusCode(),
        body = body.text,
        truncated = body.truncated
    )
}

private fun String.toBoundedText(maxChars: Int): BoundedText {
    if (length <= maxChars) {
        return BoundedText(this, truncated = false)
    }
    return BoundedText(take(maxChars), truncated = true)
}

private data class BoundedText(
    val text: String,
    val truncated: Boolean
)

private fun readTextBounded(stream: InputStream, maxChars: Int): BoundedText {
    InputStreamReader(stream, StandardCharsets.UTF_8).use { reader ->
        val out = StringBuilder()
        val chunk = CharArray(8_192)
        var remaining = maxChars
        while (true) {
            if (remaining == 0) {
                return BoundedText(out.toString(), truncated = reader.read() >= 0)
            }
            val read = reader.read(chunk, 0, minOf(chunk.size, remaining))
            if (read < 0) {
                return BoundedText(out.toString(), truncated = false)
            }
            out.append(chunk, 0, read)
            remaining -= read
        }
    }
}
