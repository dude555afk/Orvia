package me.rerere.rikkahub.data.ai.tools

import android.Manifest
import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Process
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.coroutines.resume

/**
 * Native Android port of Orvia's local location, screen-time and calendar tools.
 * The caller requires explicit approval for every tool invocation. Android
 * runtime/special permissions are independently checked here.
 */
class OrviaDeviceTools(private val context: Context) {
    suspend fun execute(payload: String): String {
        val request = try {
            JSONObject(payload)
        } catch (_: Exception) {
            return error("INVALID_ARGUMENT", "Expected a JSON object.").toString()
        }
        return try {
            when (request.optString("action")) {
                "current_location" -> currentLocation().toString()
                "screen_time" -> screenTime(request)
                "calendar_query" -> queryCalendar(request)
                "calendar_create" -> createCalendarEvent(request)
                else -> error("INVALID_ACTION", "Use current_location, screen_time, calendar_query, or calendar_create.").toString()
            }
        } catch (_: SecurityException) {
            error("NO_PERMISSION", "Android denied this operation. Enable the required permission for Orvia in Android settings, then retry.").toString()
        } catch (e: Exception) {
            error("DEVICE_TOOL_FAILED", e.message ?: "The device tool failed.").toString()
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private suspend fun currentLocation(): JSONObject {
        if (!hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION) &&
            !hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        ) {
            return error("NO_PERMISSION", "Location permission is not granted. Enable approximate or precise location for Orvia in Android app settings.")
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (!LocationManagerCompat.isLocationEnabled(manager)) {
            return error("LOCATION_DISABLED", "Location services are turned off on this device.")
        }
        val fine = hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val available = manager.getProviders(true)
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && available.contains(LocationManager.FUSED_PROVIDER)) {
                add(LocationManager.FUSED_PROVIDER)
            }
            if (available.contains(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
            if (fine && available.contains(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
        }.distinct()
        if (providers.isEmpty()) return error("LOCATION_UNAVAILABLE", "No enabled location provider is available.")

        var resolved: Location? = null
        var resolvedProvider: String? = null
        for (provider in providers) {
            val signal = CancellationSignal()
            val location = withTimeoutOrNull(10_000L) {
                suspendCancellableCoroutine<Location?> { continuation ->
                    continuation.invokeOnCancellation { signal.cancel() }
                    LocationManagerCompat.getCurrentLocation(
                        manager, provider, signal, ContextCompat.getMainExecutor(context)
                    ) { result ->
                        if (continuation.isActive) continuation.resume(result)
                    }
                }
            }
            if (location != null) {
                resolved = location
                resolvedProvider = provider
                break
            }
        }
        val lastKnownFallback = resolved == null
        if (resolved == null) {
            for (provider in providers) {
                val cached = runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
                if (cached != null && (resolved == null || cached.time > resolved!!.time)) {
                    resolved = cached
                    resolvedProvider = provider
                }
            }
        }
        val location = resolved ?: return error("LOCATION_UNAVAILABLE", "Android returned no current or cached location.")
        return JSONObject()
            .put("latitude", location.latitude)
            .put("longitude", location.longitude)
            .put("accuracy_m", if (location.hasAccuracy()) location.accuracy.toDouble() else JSONObject.NULL)
            .put("altitude_m", if (location.hasAltitude()) location.altitude else JSONObject.NULL)
            .put("provider", resolvedProvider ?: location.provider ?: "unknown")
            .put("timestamp", Instant.ofEpochMilli(location.time).toString())
            .put("last_known_fallback", lastKnownFallback)
            .put("precision", if (fine) "precise-permission" else "approximate-permission")
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        val appUri = Uri.fromParts("package", context.packageName, null)
        val target = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, appUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(target) }.onFailure {
            runCatching {
                context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun screenTime(params: JSONObject): String {
        if (!hasUsageStatsPermission()) {
            openUsageAccessSettings()
            return error("NO_PERMISSION", "Usage Access settings were opened. Enable Usage access for Orvia, return to chat, and approve the request again.").toString()
        }
        val top = params.optInt("top", 10).coerceIn(1, 50)
        val now = ZonedDateTime.now()
        val zone = now.zone
        val range = params.optString("range", "today")
        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            endTime = params.optString("end").takeIf { it.isNotBlank() }?.let { parseTime(it, zone) } ?: now
            startTime = params.optString("begin").takeIf { it.isNotBlank() }?.let { parseTime(it, zone) }
                ?: if (range == "week") now.minusDays(7) else now.toLocalDate().atStartOfDay(zone)
        } catch (e: Exception) {
            return error("INVALID_TIME", e.message ?: "Invalid begin/end time.").toString()
        }
        if (!startTime.isBefore(endTime)) return error("INVALID_RANGE", "begin must be earlier than end.").toString()

        val startMs = startTime.toInstant().toEpochMilli()
        val endMs = endTime.toInstant().toEpochMilli()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val homePackages = runCatching {
            context.packageManager.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), PackageManager.MATCH_DEFAULT_ONLY
            ).mapNotNull { it.activityInfo?.packageName }.toSet()
        }.getOrDefault(emptySet())
        val totals = HashMap<String, Long>()
        val events = manager.queryEvents(startMs - 12L * 60 * 60 * 1000, endMs)
        val event = UsageEvents.Event()
        var activePackage: String? = null
        var activeSince = 0L
        fun settle(at: Long) {
            val current = activePackage
            activePackage = null
            if (current == null || current in homePackages) return
            val duration = at - maxOf(activeSince, startMs)
            if (duration > 0) totals[current] = (totals[current] ?: 0L) + duration
        }
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (event.packageName != activePackage) {
                        settle(event.timeStamp)
                        activePackage = event.packageName
                        activeSince = event.timeStamp
                    }
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> if (event.packageName == activePackage) settle(event.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> settle(event.timeStamp)
            }
        }
        settle(endMs)
        val ordered = totals.entries.filter { it.value > 0 }.sortedByDescending { it.value }
        val apps = JSONArray()
        ordered.take(top).forEach { row ->
            val name = runCatching {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(row.key, 0)).toString()
            }.getOrDefault(row.key)
            apps.put(JSONObject().put("package", row.key).put("app_name", name)
                .put("total_ms", row.value).put("total_minutes", row.value / 60_000))
        }
        return JSONObject().put("range", range)
            .put("start", startTime.withNano(0).toString())
            .put("end", endTime.withNano(0).toString())
            .put("total_ms", ordered.sumOf { it.value })
            .put("total_minutes", ordered.sumOf { it.value } / 60_000)
            .put("apps", apps).toString()
    }

    private fun queryCalendar(params: JSONObject): String {
        if (!hasPermission(Manifest.permission.READ_CALENDAR)) {
            return error("NO_PERMISSION", "Calendar read permission is not granted. Enable Calendar permission for Orvia in Android app settings.").toString()
        }
        val limit = params.optInt("limit", 20).coerceIn(1, 100)
        val query = params.optString("query").takeIf { it.isNotBlank() }
        val now = ZonedDateTime.now()
        val zone = now.zone
        val range = params.optString("range", "today")
        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            startTime = params.optString("begin").takeIf { it.isNotBlank() }?.let { parseTime(it, zone) }
                ?: when (range) {
                    "week" -> now.toLocalDate().atStartOfDay(zone).minusDays(now.dayOfWeek.value.toLong() - 1)
                    "month" -> now.toLocalDate().withDayOfMonth(1).atStartOfDay(zone)
                    else -> now.toLocalDate().atStartOfDay(zone)
                }
            endTime = params.optString("end").takeIf { it.isNotBlank() }?.let { parseTime(it, zone) }
                ?: if (params.optString("begin").isNotBlank()) now else when (range) {
                    "week" -> startTime.plusDays(7)
                    "month" -> startTime.plusMonths(1)
                    else -> now.toLocalDate().plusDays(1).atStartOfDay(zone)
                }
        } catch (e: Exception) {
            return error("INVALID_TIME", e.message ?: "Invalid begin/end time.").toString()
        }
        if (!startTime.isBefore(endTime)) return error("INVALID_RANGE", "begin must be earlier than end.").toString()
        val beginMs = startTime.toInstant().toEpochMilli()
        val endMs = endTime.toInstant().toEpochMilli()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION, CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.BEGIN, CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
        )
        val selection = if (query != null) CalendarContract.Instances.TITLE + " LIKE ? ESCAPE '\\\\'" else null
        val selectionArgs = if (query != null) arrayOf("%" + query.replace("%", "\\%").replace("_", "\\_") + "%") else null
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(beginMs.toString()).appendPath(endMs.toString()).build()
        val rows = JSONArray()
        context.contentResolver.query(uri, projection, selection, selectionArgs, CalendarContract.Instances.BEGIN + " ASC")?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
            val titleCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
            val descriptionCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION)
            val locationCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)
            val beginCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
            val endCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.END)
            val allDayCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
            val calendarCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
            var count = 0
            while (cursor.moveToNext() && count < limit) {
                rows.put(JSONObject()
                    .put("event_id", cursor.getLong(idCol))
                    .put("title", cursor.getString(titleCol) ?: "")
                    .put("description", cursor.getString(descriptionCol) ?: "")
                    .put("location", cursor.getString(locationCol) ?: "")
                    .put("start_ms", cursor.getLong(beginCol))
                    .put("end_ms", cursor.getLong(endCol))
                    .put("all_day", cursor.getInt(allDayCol) != 0)
                    .put("calendar", cursor.getString(calendarCol) ?: ""))
                count++
            }
        }
        return JSONObject().put("range", range)
            .put("start", startTime.withNano(0).toString())
            .put("end", endTime.withNano(0).toString())
            .put("events", rows).toString()
    }

    private fun createCalendarEvent(params: JSONObject): String {
        if (!hasPermission(Manifest.permission.WRITE_CALENDAR)) {
            return error("NO_PERMISSION", "Calendar write permission is not granted. Enable Calendar permission for Orvia in Android app settings.").toString()
        }
        val title = params.optString("title").takeIf { it.isNotBlank() }
            ?: return error("MISSING_REQUIRED", "title is required.").toString()
        val startRaw = params.optString("start").takeIf { it.isNotBlank() }
            ?: return error("MISSING_REQUIRED", "start is required as ISO-8601 date/date-time or epoch milliseconds.").toString()
        val allDay = params.optBoolean("all_day", false)
        val zone = ZoneId.systemDefault()
        val startTime: ZonedDateTime
        val endTime: ZonedDateTime
        try {
            startTime = parseTime(startRaw, zone)
            endTime = params.optString("end").takeIf { it.isNotBlank() }?.let { parseTime(it, zone) }
                ?: if (allDay) startTime.toLocalDate().plusDays(1).atStartOfDay(zone) else startTime.plusHours(1)
        } catch (e: Exception) {
            return error("INVALID_TIME", e.message ?: "Invalid event time.").toString()
        }
        if (!startTime.isBefore(endTime)) return error("INVALID_RANGE", "end must be later than start.").toString()

        val eventStart: Long
        val eventEnd: Long
        val eventZone: String
        if (allDay) {
            val startDate = startTime.toLocalDate()
            val endDate = endTime.toLocalDate()
            if (!startDate.isBefore(endDate)) return error("INVALID_RANGE", "All-day event end date must be after its start date.").toString()
            eventStart = startDate.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
            eventEnd = endDate.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
            eventZone = "UTC"
        } else {
            eventStart = startTime.toInstant().toEpochMilli()
            eventEnd = endTime.toInstant().toEpochMilli()
            eventZone = zone.id
        }
        val calendarId = defaultWritableCalendarId()
            ?: return error("NO_CALENDAR", "No writable calendar account is available on this device.").toString()
        val description = params.optString("description")
        val location = params.optString("location")
        val reminders = parseReminderMinutes(params.opt("reminders"))
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.EVENT_LOCATION, location)
            put(CalendarContract.Events.DTSTART, eventStart)
            put(CalendarContract.Events.DTEND, eventEnd)
            put(CalendarContract.Events.EVENT_TIMEZONE, eventZone)
            put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
            put(CalendarContract.Events.HAS_ALARM, if (reminders.isEmpty()) 0 else 1)
        }
        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: return error("CREATE_FAILED", "Android did not create the calendar event.").toString()
        val eventId = uri.lastPathSegment?.toLongOrNull()
        val savedReminders = if (eventId == null) emptyList() else insertReminders(eventId, reminders)
        return JSONObject().put("success", true).put("event_uri", uri.toString())
            .put("event_id", eventId ?: JSONObject.NULL).put("title", title)
            .put("start", startTime.withNano(0).toString()).put("end", endTime.withNano(0).toString())
            .put("reminders_saved_minutes_before", JSONArray(savedReminders)).toString()
    }

    private fun defaultWritableCalendarId(): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val selection = CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL + " >= ? AND " +
            CalendarContract.Calendars.SYNC_EVENTS + " = 1"
        val args = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection,
            selection + " AND " + CalendarContract.Calendars.IS_PRIMARY + " = 1",
            args, null,
        )?.use { cursor -> if (cursor.moveToFirst()) return cursor.getLong(0) }
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection, selection, args,
            CalendarContract.Calendars.VISIBLE + " DESC",
        )?.use { cursor -> if (cursor.moveToFirst()) return cursor.getLong(0) }
        return null
    }

    private fun parseReminderMinutes(value: Any?): List<Int> {
        val array = value as? JSONArray ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optInt(it, -1).takeIf { m -> m in 0..10_080 } }
            .distinct().take(5)
    }

    private fun insertReminders(eventId: Long, minutes: List<Int>): List<Int> {
        val saved = mutableListOf<Int>()
        for (minute in minutes) {
            val values = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, minute)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            if (runCatching { context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, values) }.getOrNull() != null) {
                saved.add(minute)
            }
        }
        return saved
    }

    private fun parseTime(raw: String, zone: ZoneId): ZonedDateTime {
        val text = raw.trim()
        text.toLongOrNull()?.let { return Instant.ofEpochMilli(it).atZone(zone) }
        runCatching { OffsetDateTime.parse(text).atZoneSameInstant(zone) }.getOrNull()?.let { return it }
        runCatching { Instant.parse(text).atZone(zone) }.getOrNull()?.let { return it }
        runCatching { LocalDateTime.parse(text).atZone(zone) }.getOrNull()?.let { return it }
        runCatching { LocalDate.parse(text).atStartOfDay(zone) }.getOrNull()?.let { return it }
        throw IllegalArgumentException("Invalid time format: '" + text + "'. Use ISO-8601 date/date-time or epoch milliseconds.")
    }

    private fun error(code: String, message: String): JSONObject =
        JSONObject().put("error", code).put("message", message)
}
