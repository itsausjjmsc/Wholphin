package com.github.damontecres.wholphin.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

class SeriesTrackChoiceMigrationTest {
    private val seriesId = UUID.randomUUID()

    @Test
    fun disabledSubtitlesAreMigrated() {
        // The old writer saved subtitleLanguage = null whenever subtitles were disabled
        val plc =
            PlaybackLanguageChoice(
                userId = 1,
                seriesId = seriesId,
                audioLanguage = "eng",
                subtitleLanguage = null,
                subtitlesDisabled = true,
            )

        val choices = SeriesTrackChoice.from(plc)

        val subtitle = choices.single { it.type == SeriesTrackChoiceType.SUBTITLE }
        assertEquals(ActivationFlag.DISABLED, subtitle.activation)
        assertNull(subtitle.language)
        assertEquals(1, choices.count { it.type == SeriesTrackChoiceType.AUDIO })
    }

    @Test
    fun enabledSubtitlesAreMigrated() {
        val plc =
            PlaybackLanguageChoice(
                userId = 1,
                seriesId = seriesId,
                subtitleLanguage = "spa",
                subtitlesDisabled = false,
            )

        val subtitle = SeriesTrackChoice.from(plc).single { it.type == SeriesTrackChoiceType.SUBTITLE }
        assertEquals(ActivationFlag.ACTIVATED, subtitle.activation)
        assertEquals("spa", subtitle.language)
    }

    @Test
    fun noSubtitleChoiceWhenNothingWasSaved() {
        val plc =
            PlaybackLanguageChoice(
                userId = 1,
                seriesId = seriesId,
                audioLanguage = "eng",
            )

        assertEquals(0, SeriesTrackChoice.from(plc).count { it.type == SeriesTrackChoiceType.SUBTITLE })
    }
}
