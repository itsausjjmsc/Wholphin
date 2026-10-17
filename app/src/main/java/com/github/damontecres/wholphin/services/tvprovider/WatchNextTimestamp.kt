package com.github.damontecres.wholphin.services.tvprovider

import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Android TV's Watch Next API requires milliseconds since the epoch, not Unix seconds.
 *
 * The SDK parses the server's 0001-01-01 placeholder as [LocalDateTime.MIN], which overflows
 * epoch milliseconds, so dates that can't be converted fall back to [nowMillis] like a missing date.
 */
internal fun watchNextEngagementTimeMillis(
    lastPlayedDate: LocalDateTime?,
    zoneId: ZoneId = ZoneId.systemDefault(),
    nowMillis: Long = System.currentTimeMillis(),
): Long =
    lastPlayedDate?.let {
        try {
            it.atZone(zoneId).toInstant().toEpochMilli()
        } catch (_: ArithmeticException) {
            null
        }
    } ?: nowMillis
