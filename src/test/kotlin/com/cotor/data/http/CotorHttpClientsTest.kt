package com.cotor.data.http

import com.sun.net.httpserver.HttpServer
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldStartWith
import java.net.InetSocketAddress
import java.net.URI
import java.net.http.HttpRequest
import java.time.Duration
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

class CotorHttpClientsTest : FunSpec({
    test("reuses the default HTTP client to avoid per-call selector thread growth") {
        val first = CotorHttpClients.newClient()
        val second = CotorHttpClients.newClient()

        (first === second) shouldBe true
    }

    test("reuses timeout-specific HTTP clients") {
        val first = CotorHttpClients.client(Duration.ofSeconds(20))
        val second = CotorHttpClients.client(Duration.ofSeconds(20))
        val differentTimeout = CotorHttpClients.client(Duration.ofSeconds(5))

        (first === second) shouldBe true
        (first === differentTimeout) shouldBe false
    }

    test("uses daemon executor threads so HTTP clients do not keep the JVM alive") {
        val executor = CotorHttpClients.newClient().executor().orElseThrow() as ExecutorService

        val result = executor.submit<Pair<Boolean, String>> {
            Thread.currentThread().isDaemon to Thread.currentThread().name
        }.get(2, TimeUnit.SECONDS)

        result.first shouldBe true
        result.second shouldStartWith "cotor-http-"
    }

    test("sendBoundedText caps oversized response bodies") {
        val body = "x".repeat(50_000)
        val server = localTextServer(body)
        try {
            val port = server.address.port
            val request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:$port/"))
                .GET()
                .build()

            val response = CotorHttpClients.newClient().sendBoundedText(request, bodyLimitChars = 1_024)

            response.statusCode shouldBe 200
            response.body.length shouldBe 1_024
            response.truncated shouldBe true
            response.diagnosticBody() shouldContain "cotor truncated HTTP response body"
        } finally {
            server.stop(0)
        }
    }

    test("sendBoundedText preserves complete small response bodies") {
        val server = localTextServer("ok")
        try {
            val port = server.address.port
            val request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:$port/"))
                .GET()
                .build()

            val response = CotorHttpClients.newClient().sendBoundedText(request, bodyLimitChars = 1_024)

            response.statusCode shouldBe 200
            response.body shouldBe "ok"
            response.truncated shouldBe false
        } finally {
            server.stop(0)
        }
    }
})

private fun localTextServer(body: String): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/") { exchange ->
        val bytes = body.toByteArray()
        exchange.sendResponseHeaders(200, bytes.size.toLong())
        exchange.responseBody.use { it.write(bytes) }
    }
    server.start()
    return server
}
