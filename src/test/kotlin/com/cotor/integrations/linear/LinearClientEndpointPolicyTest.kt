package com.cotor.integrations.linear

import com.cotor.app.LinearConnectionConfig
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.string.shouldContain

class LinearClientEndpointPolicyTest : FunSpec({
    test("rejects private Linear GraphQL endpoints before sending a request") {
        val result = LinearClient().graphql(
            config = LinearConnectionConfig(
                endpoint = "http://127.0.0.1:8080/graphql",
                apiToken = "linear-token"
            ),
            query = "query CotorLinearViewer { viewer { id } }"
        )

        result.isFailure.shouldBeTrue()
        result.exceptionOrNull()?.message shouldContain "private network"
    }
})
