package com.cotor.security

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import java.net.InetAddress

class NetworkEndpointPolicyTest : FunSpec({
    test("accepts public http and https endpoints") {
        val publicResolver: (String) -> List<InetAddress> = { listOf(InetAddress.getByName("93.184.216.34")) }
        NetworkEndpointPolicy.requirePublicHttpUrl(
            rawUrl = "https://api.linear.app/graphql",
            label = "Linear endpoint",
            resolver = publicResolver
        ).host shouldBe "api.linear.app"
        NetworkEndpointPolicy.requirePublicHttpUrl(
            rawUrl = "http://example.com/v1",
            label = "OpenAI baseUrl",
            resolver = publicResolver
        ).scheme shouldBe "http"
    }

    test("rejects localhost private and credential-bearing endpoints by default") {
        shouldThrow<IllegalArgumentException> {
            NetworkEndpointPolicy.requirePublicHttpUrl("http://127.0.0.1:8080/graphql", "Linear endpoint")
        }.message shouldContain "private"

        shouldThrow<IllegalArgumentException> {
            NetworkEndpointPolicy.requirePublicHttpUrl("http://192.168.1.10:8080/v1", "OpenAI baseUrl")
        }.message shouldContain "private"

        shouldThrow<IllegalArgumentException> {
            NetworkEndpointPolicy.requirePublicHttpUrl("https://user:pass@example.com/v1", "OpenAI baseUrl")
        }.message shouldContain "credentials"
    }

    test("allows private endpoints only when an integration explicitly opts in") {
        val uri = NetworkEndpointPolicy.requirePublicHttpUrl(
            rawUrl = "http://127.0.0.1:11434/v1",
            label = "OpenAI baseUrl",
            allowPrivateHosts = true
        )
        uri.host shouldBe "127.0.0.1"
    }

    test("rejects public-looking hosts that resolve to private addresses") {
        shouldThrow<IllegalArgumentException> {
            NetworkEndpointPolicy.requirePublicHttpUrl(
                rawUrl = "https://internal.example.test/v1",
                label = "OpenAI baseUrl",
                resolver = { listOf(InetAddress.getByName("127.0.0.1")) }
            )
        }.message shouldContain "private"

        shouldThrow<IllegalArgumentException> {
            NetworkEndpointPolicy.requirePublicHttpUrl(
                rawUrl = "https://metadata.example.test/v1",
                label = "OpenAI baseUrl",
                resolver = { listOf(InetAddress.getByName("169.254.169.254")) }
            )
        }.message shouldContain "private"
    }
})
