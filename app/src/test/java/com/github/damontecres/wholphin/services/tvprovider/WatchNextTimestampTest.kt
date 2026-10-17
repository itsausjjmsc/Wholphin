package com.github.damontecres.wholphin.services.tvprovider

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

class WatchNextTimestampTest {
    @Test
    fun `last played time is expressed in epoch milliseconds rather than seconds`() {
        val date = LocalDateTime.of(2026, 10, 16, 12, 34, 56)
        val epochMillis = Instant.parse("2026-10-16T12:34:56Z").toEpochMilli()

        assertEquals(epochMillis, watchNextEngagementTimeMillis(date, ZoneId.of("UTC"), 0L))
        assertEquals(date.atZone(ZoneId.of("UTC")).toEpochSecond() * 1000, epochMillis)
    }

    @Test
    fun `preserves the user's timezone when converting local date time`() {
        val date = LocalDateTime.of(2026, 10, 16, 15, 0)
        val expected = Instant.parse("2026-10-16T22:00:00Z").toEpochMilli()

        assertEquals(expected, watchNextEngagementTimeMillis(date, ZoneId.of("America/Phoenix"), 0L))
    }

    @Test
    fun `preserves millisecond precision`() {
        val date = LocalDateTime.of(2026, 10, 16, 12, 34, 56, 123_000_000)
        val expected = Instant.parse("2026-10-16T12:34:56.123Z").toEpochMilli()

        assertEquals(expected, watchNextEngagementTimeMillis(date, ZoneId.of("UTC"), 0L))
    }

    @Test
    fun `uses current time when no play date exists`() {
        assertEquals(987_654_321_000L, watchNextEngagementTimeMillis(null, ZoneId.of("UTC"), 987_654_321_000L))
    }
}
