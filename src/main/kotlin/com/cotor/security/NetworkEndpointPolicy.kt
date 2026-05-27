package com.cotor.security

import java.net.URI
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Validates user-configurable HTTP endpoints before outbound clients use them.
 */
object NetworkEndpointPolicy {
    fun requirePublicHttpUrl(
        rawUrl: String,
        label: String,
        allowPrivateHosts: Boolean = false,
        resolver: (String) -> List<InetAddress> = { host -> InetAddress.getAllByName(host).toList() }
    ): URI {
        val trimmed = rawUrl.trim()
        require(trimmed.isNotBlank()) { "$label is required" }

        val uri = runCatching { URI(trimmed) }
            .getOrElse { throw IllegalArgumentException("$label must be a valid URI") }
            .normalize()
        val scheme = uri.scheme?.lowercase()
        require(scheme == "https" || scheme == "http") { "$label must use http or https" }
        require(!uri.host.isNullOrBlank()) { "$label must include a host" }
        require(uri.userInfo == null) { "$label must not include credentials" }

        if (!allowPrivateHosts) {
            val host = uri.host.trim().trim('[', ']').lowercase()
            require(!isPrivateOrLocalHost(host)) { "$label must not target localhost or a private network address" }
            val resolvedAddresses = runCatching { resolver(host) }
                .getOrElse { throw IllegalArgumentException("$label host could not be resolved") }
            require(resolvedAddresses.isNotEmpty()) { "$label host could not be resolved" }
            require(resolvedAddresses.none(::isPrivateOrLocalAddress)) {
                "$label must not resolve to localhost or a private network address"
            }
        }

        return uri
    }

    private fun isPrivateOrLocalHost(host: String): Boolean {
        if (host == "localhost" || host.endsWith(".localhost") || host == "0") return true
        if (host == "::1" || host == "0:0:0:0:0:0:0:1") return true

        parseIpv4(host)?.let { octets ->
            val first = octets[0]
            val second = octets[1]
            return first == 0 ||
                first == 10 ||
                first == 127 ||
                first == 169 && second == 254 ||
                first == 172 && second in 16..31 ||
                first == 192 && second == 168
        }

        if (host.contains(":")) {
            val normalized = host.lowercase()
            return normalized.startsWith("fc") ||
                normalized.startsWith("fd") ||
                normalized.startsWith("fe80") ||
                normalized == "::" ||
                normalized.startsWith("::ffff:127.") ||
                normalized.startsWith("::ffff:10.") ||
                normalized.startsWith("::ffff:192.168.")
        }

        return false
    }

    private fun isPrivateOrLocalAddress(address: InetAddress): Boolean {
        if (
            address.isAnyLocalAddress ||
            address.isLoopbackAddress ||
            address.isLinkLocalAddress ||
            address.isSiteLocalAddress ||
            address.isMulticastAddress
        ) {
            return true
        }
        return when (address) {
            is Inet4Address -> {
                val bytes = address.address.map { it.toInt() and 0xff }
                val first = bytes[0]
                val second = bytes[1]
                first == 0 ||
                    first == 10 ||
                    first == 127 ||
                    first == 169 && second == 254 ||
                    first == 172 && second in 16..31 ||
                    first == 192 && second == 168 ||
                    first == 100 && second in 64..127
            }
            is Inet6Address -> {
                val bytes = address.address
                val first = bytes[0].toInt() and 0xff
                val second = bytes[1].toInt() and 0xff
                first == 0xfc ||
                    first == 0xfd ||
                    first == 0xfe && (second and 0xc0) == 0x80
            }
            else -> false
        }
    }

    private fun parseIpv4(host: String): List<Int>? {
        val parts = host.split('.')
        if (parts.size != 4) return null
        return parts.map { part ->
            if (part.isEmpty() || part.any { !it.isDigit() }) return null
            part.toIntOrNull()?.takeIf { it in 0..255 } ?: return null
        }
    }
}
