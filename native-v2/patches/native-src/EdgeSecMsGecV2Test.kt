package me.rerere.tts.provider.android

import org.junit.Assert.assertEquals
import org.junit.Test

class EdgeSecMsGecV2Test {
    @Test
    fun matchesReferenceV2TokenVector() {
        assertEquals(
            "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2",
            EdgeSecMsGecV2.generate(1_700_000_000L),
        )
    }
}
