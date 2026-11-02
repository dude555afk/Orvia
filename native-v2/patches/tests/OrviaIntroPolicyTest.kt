package me.rerere.rikkahub.ui.components

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OrviaIntroPolicyTest {
    @Test
    fun showsOnlyOnAnUnrestoredLauncherColdStart() {
        assertTrue(
            OrviaIntroPolicy.shouldShow(
                savedStatePresent = false,
                action = Intent.ACTION_MAIN,
                categories = setOf(Intent.CATEGORY_LAUNCHER),
            ),
        )
    }

    @Test
    fun restoredLauncherActivityDoesNotReplayIntro() {
        assertFalse(
            OrviaIntroPolicy.shouldShow(
                savedStatePresent = true,
                action = Intent.ACTION_MAIN,
                categories = setOf(Intent.CATEGORY_LAUNCHER),
            ),
        )
    }

    @Test
    fun deepLinksAndNonLauncherEntriesSkipIntro() {
        assertFalse(
            OrviaIntroPolicy.shouldShow(
                savedStatePresent = false,
                action = Intent.ACTION_VIEW,
                categories = setOf(Intent.CATEGORY_LAUNCHER),
            ),
        )
        assertFalse(
            OrviaIntroPolicy.shouldShow(
                savedStatePresent = false,
                action = Intent.ACTION_MAIN,
                categories = emptySet(),
            ),
        )
    }

    @Test
    fun introDurationIncludesAnimationAndSettleWindow() {
        assertEquals(1_050, OrviaIntroPolicy.animationDurationMillis)
        assertEquals(220L, OrviaIntroPolicy.settleDelayMillis)
        assertEquals(1_270L, OrviaIntroPolicy.totalDurationMillis)
    }
}
