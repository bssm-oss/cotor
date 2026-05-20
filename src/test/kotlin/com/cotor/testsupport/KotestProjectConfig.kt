package com.cotor.testsupport

import io.kotest.common.ExperimentalKotest
import io.kotest.core.config.AbstractProjectConfig
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalKotest::class)
object KotestProjectConfig : AbstractProjectConfig() {
    override val parallelism = 1
    override val concurrentSpecs = 1
    override val concurrentTests = 1
    override val timeout = 180.seconds
}
