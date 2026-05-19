package com.cotor.app

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldStartWith

class DesktopEndpointPolicyTest : FunSpec({

    test("loopback 127.0.0.1 URL is allowed without any env flag") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint("http://127.0.0.1:8787")
        endpoint shouldBe "http://127.0.0.1:8787/api/a2a"
    }

    test("loopback localhost URL is allowed without any env flag") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint("http://localhost:8787")
        endpoint shouldBe "http://localhost:8787/api/a2a"
    }

    test("null env URL falls back to default loopback") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint(null)
        endpoint shouldBe DesktopEndpointPolicy.DEFAULT_LOOPBACK_A2A
    }

    test("blank env URL falls back to default loopback") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint("   ")
        endpoint shouldBe DesktopEndpointPolicy.DEFAULT_LOOPBACK_A2A
    }

    test("remote URL without allow flag falls back to default loopback") {
        val origFlag = System.getenv("COTOR_ALLOW_REMOTE_APP_SERVER")
        val origToken = System.getenv("COTOR_APP_TOKEN")
        try {
            // Neither flag nor token set — remote should be blocked
            val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint("https://remote.example.com:8787")
            endpoint shouldBe DesktopEndpointPolicy.DEFAULT_LOOPBACK_A2A
        } finally {
            // env vars are read-only in tests, so just verify the policy logic below
        }
    }

    test("isLoopback returns true for 127.0.0.1 variants") {
        DesktopEndpointPolicy.isLoopback("http://127.0.0.1:8787") shouldBe true
        DesktopEndpointPolicy.isLoopback("http://127.0.0.1:9999/something") shouldBe true
        DesktopEndpointPolicy.isLoopback("https://127.0.0.1") shouldBe true
        DesktopEndpointPolicy.isLoopback("http://localhost:8787") shouldBe true
        DesktopEndpointPolicy.isLoopback("http://[::1]:8787") shouldBe true
    }

    test("isLoopback returns false for remote hosts") {
        DesktopEndpointPolicy.isLoopback("https://api.cotor.io") shouldBe false
        DesktopEndpointPolicy.isLoopback("http://10.0.0.1:8787") shouldBe false
        DesktopEndpointPolicy.isLoopback("http://192.168.1.100:8787") shouldBe false
        DesktopEndpointPolicy.isLoopback("http://localhost.evil.test:8787") shouldBe false
        DesktopEndpointPolicy.isLoopback("http://127.0.0.1.evil.test:8787") shouldBe false
        DesktopEndpointPolicy.isLoopback("ftp://localhost:8787") shouldBe false
    }

    test("trailing slash is stripped before appending api/a2a") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint("http://127.0.0.1:8787/")
        endpoint shouldBe "http://127.0.0.1:8787/api/a2a"
    }

    test("remote URL is allowed only with explicit flag and token") {
        val endpoint = DesktopEndpointPolicy.resolveA2aEndpoint(
            envUrl = "https://remote.example.com:8787",
            envAllowRemote = "1",
            envToken = "token"
        )
        endpoint shouldBe "https://remote.example.com:8787/api/a2a"
    }
})
