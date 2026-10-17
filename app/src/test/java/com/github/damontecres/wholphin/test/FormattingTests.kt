package com.github.damontecres.wholphin.test

import com.github.damontecres.wholphin.ui.abbreviateNumber
import com.github.damontecres.wholphin.ui.formatBitrate
import com.github.damontecres.wholphin.ui.formatBytes
import com.github.damontecres.wholphin.ui.util.StreamFormatting.resolutionString
import org.junit.Assert
import org.junit.Test
import java.util.Locale

class FormattingTests {
    @Test
    fun testResolutionStrings() {
        Assert.assertEquals("4K", resolutionString(3840, 2160, false))
        Assert.assertEquals("1080p", resolutionString(1920, 1080, false))
        Assert.assertEquals("720p", resolutionString(1280, 720, false))
        Assert.assertEquals("480i", resolutionString(640, 480, true))

        Assert.assertEquals("576p", resolutionString(1024, 576, false))
        Assert.assertEquals("576p", resolutionString(960, 576, false))

        // 21:9
        Assert.assertEquals("1080p", resolutionString(1920, 822, false))

        Assert.assertEquals("1440p", resolutionString(2560, 1440, false))
    }

    private fun format(
        pattern: String,
        vararg args: Any,
    ) = String.format(Locale.getDefault(), pattern, *args)

    @Test
    fun testAbbreviateNumber() {
        Assert.assertEquals("999", abbreviateNumber(999))
        Assert.assertEquals(format("%.1f%s", 1.0, "K"), abbreviateNumber(1000))
        Assert.assertEquals(format("%.1f%s", 5.5, "K"), abbreviateNumber(5533))
        Assert.assertEquals(format("%.1f%s", 999.9, "K"), abbreviateNumber(999_949))
        // Values that round up to the next unit use that unit
        Assert.assertEquals(format("%.1f%s", 1.0, "M"), abbreviateNumber(999_950))
        Assert.assertEquals(format("%.1f%s", 1.0, "M"), abbreviateNumber(999_999))
        Assert.assertEquals(format("%.1f%s", 1.0, "B"), abbreviateNumber(999_950_000))
    }

    @Test
    fun testFormatBytes() {
        Assert.assertEquals(format("%.2f %s", 1023.0, "B"), formatBytes(1023))
        Assert.assertEquals(format("%.2f %s", 1.0, "KiB"), formatBytes(1024))
        Assert.assertEquals(format("%.2f %s", 1023.99, "KiB"), formatBytes(1_048_570))
        Assert.assertEquals(format("%.2f %s", 1.0, "MiB"), formatBytes(1_048_575))
        Assert.assertEquals(format("%.2f %s", 1.0, "GiB"), formatBytes(1_073_741_823))
        Assert.assertEquals(format("%.2f %s", 1.0, "mbps"), formatBitrate(999_999))
        Assert.assertEquals(format("%.2f %s", 8.0, "mbps"), formatBitrate(8_000_000))
    }
}
