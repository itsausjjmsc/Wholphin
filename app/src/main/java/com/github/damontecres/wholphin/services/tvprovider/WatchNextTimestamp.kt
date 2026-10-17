package com.github.damontecres.wholphin.services.tvprovider

import java.time.LocalDateTime
import java.time.ZoneId

/** Android TV's Watch Next API requires milliseconds since the epoch, not Unix seconds. */
internal fun watchNextEngagementTimeMillis(
    lastPlayedDate: LocalDateTime?,
    zoneId: ZoneId = ZoneId.systemDefault(),
    nowMillis: Long = System.currentTimeMillis(),
): Long = lastPlayedDate?.atZone(zoneId)?.toInstant()?.toEpochMilli() ?: nowMillis
