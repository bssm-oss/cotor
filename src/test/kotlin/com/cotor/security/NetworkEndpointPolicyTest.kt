package com.cotor.security

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain

class NetworkEndpointPolicyTest : FunSpec({
    test("accepts public http and https endpoints") {
        NetworkEndpointPolicy.requirePublicHttpUrl("https://api.linear.app/graphql", "Linear endpoint").host shouldBe "api.linear.app"
        NetworkEndpointPolicy.requirePublicHttpUrl("http://example.com/v1", "OpenAI baseUrl").scheme shouldBe "http"
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
})
