package com.dude555afk.orvia

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.util.concurrent.Executors

class DeviceLocalToolsHandler(private val context: Context) {
    private var attachedActivity: Activity? = context as? Activity
    private val activity: Activity get() = requireNotNull(attachedActivity) { "foreground_activity_required" }
    fun attachActivity(activity: Activity) { attachedActivity = activity }
    fun detachActivity(activity: Activity) {
        if (attachedActivity !== activity) return
        attachedActivity = null
        pendingCalendarPermissionCallback?.invoke(false)
        pendingCalendarPermissionCallback = null
        pendingLocationPermissionCallback?.invoke(false, false)
        pendingLocationPermissionCallback = null
    }
    companion object {
        const val CHANNEL_NAME = "app.device_tools"
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4201
        const val LOCATION_PERMISSION_REQUEST_CODE = 4202
    }
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingCalendarPermissionCallback: ((Boolean) -> Unit)?
    private var pendingLocationPermissionCallback: ((Boolean, Boolean) -> Unit)?
    private val locationHandler = LocationToolHandler(context)

    fun configure(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            val argsJson = call.arguments as? String ?: "{}"
            when (call.method) {
                "phoneControlStatus" -> result.success(PhoneControlService.status(context))
                "phoneControl" -> PhoneControlService.execute(argsJson) { result.success(it) }
                "openAccessibilitySettings" -> { try { activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) } catch (e: Exception) {} result.success(null) }
                "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
                "openUsageAccessSettings" -> { openUsageAccessSettings(); result.success(null) }
                "hasCalendarPermission" -> result.success(hasCalendarPermission())
                "requestCalendarPermission" -> requestCalendarPermission(result)
                "hasLocationPermission" -> result.success(locationHandler.hasPermission())
                "requestLocationPermission" -> requestLocationPermission { granted, permanentlyDenied ->
                    if (permanentlyDenied) result.error("LOCATION_PERMISSION_PERMANENTLY_DENIED", "Allow location permission in system Settings.", null)
                    else result.success(granted)
                }
                "openAppSettings" -> {
                    try { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))) }
                    catch (_: Exception) { result.error("SETTINGS_UNAVAILABLE", null, null) }
                }
                "getCurrentLocation" -> { if (locationHandler.hasPermission()) locationHandler.getCurrentLocation(result) else requestLocationPermission { granted, _ -> if (granted) locationHandler.getCurrentLocation(result) else result.success(errorPayload("NO_PERMISSION", "Location permission is not granted.")) } }
                "getScreenTime" -> handleScreenTime(argsJson, result)
                "queryCalendar" -> withCalendarPermission(arrayOf(Manifest.permission.READ_CALENDAR), result) { runAsync(result) { queryCalendar(JSONObject(argsJson)) } }
                "createCalendarEvent" -> withCalendarPermission(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR), result) { runAsync(result) { createCalendarEvent(JSONObject(argsJson)) } }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val callback = pendingLocationPermissionCallback; pendingLocationPermissionCallback = null
            val granted = locationHandler.hasPermission()
            val permanentlyDenied = attachedActivity != null && !granted && grantResults.isNotEmpty() && !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION) && !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION)
            callback?.invoke(granted, permanentlyDenied); return true
        }
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) return false
        val callback = pendingCalendarPermissionCallback ?: return true
        pendingCalendarPermissionCallback = null
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        callback(granted); return true
    }

    fun dispose() { locationHandler.dispose(); pendingLocationPermissionCallback?.invoke(false, false); pendingLocationPermissionCallback = null }

    private fun requestLocationPermission(completion: (Boolean, Boolean) -> Unit) {
        if (locationHandler.hasPermission()) { completion(true, false); return }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) { completion(false, false); return }
        if (attachedActivity == null) { completion(false, false); return }
        pendingLocationPermissionCallback = completion
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), LOCATION_PERMISSION_REQUEST_CODE)
    }
    private fun calendarPermissions() = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
    private fun hasCalendarPermission() = calendarPermissions().all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    private fun requestCalendarPermission(result: MethodChannel.Result) {
        val missing = calendarPermissions().filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { result.success(true); return }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) { result.success(false); return }
        if (attachedActivity == null) { result.success(false); return }
        pendingCalendarPermissionCallback = { granted -> result.success(granted) }
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), CALENDAR_PERMISSION_REQUEST_CODE)
    }
    private fun withCalendarPermission(permissions: Array<String>, result: MethodChannel.Result, action: () -> Unit) {
        val missing = permissions.filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { action(); return }
        if (pendingCalendarPermissionCallback != null || pendingLocationPermissionCallback != null) { result.success(errorPayload("PERMISSION_REQUEST_IN_PROGRESS", "Another permission request is already in progress.")); return }
        if (attachedActivity == null) { result.success(errorPayload("FOREGROUND_REQUIRED", "Open Orvia to grant calendar permission.")); return }
        pendingCalendarPermissionCallback = { granted -> if (granted) action() else result.success(errorPayload("NO_PERMISSION", "Calendar permission is not granted.")) }
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), CALENDAR_PERMISSION_REQUEST_CODE)
    }
    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName) == AppOpsManager.MODE_ALLOWED
        } else @Suppress("DEPRECATION") {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName) == AppOpsManager.MODE_ALLOWED
        }
    }
    private fun openUsageAccessSettings() {
        try { activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.fromParts("package", context.packageName, null))) }
        catch (_: Exception) { try { activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) } catch (_: Exception) {} }
    }
    private fun runAsync(result: MethodChannel.Result, block: () -> String) {
        executor.execute { val payload = try { block() } catch (e: Exception) { errorPayload("EXECUTION_ERROR", e.message ?: "Tool execution failed.") }; mainHandler.post { result.success(payload) } }
    }
    private fun errorPayload(error: String, message: String) = JSONObject().put("error", error).put("message", message).toString()

    private fun handleScreenTime(argsJson: String, result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) { openUsageAccessSettings(); result.success(errorPayload("NO_PERMISSION", "Usage access permission is not granted.")); return }
        runAsync(result) { computeScreenTime(JSONObject(argsJson)) }
    }
    private fun computeScreenTime(params: JSONObject): String {
        val top = params.optString("top").toIntOrNull()?.coerceIn(1, 50) ?: params.optInt("top", 10).coerceIn(1, 50)
        val now = ZonedDateTime.now(); val zone = now.zone
        val beginRaw = params.optString("begin").takeIf { it.isNotBlank() }; val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val rangePreset = params.optString("range").takeIf { it.isNotBlank() } ?: "today"
        val startTime: ZonedDateTime; val endTime: ZonedDateTime
        try {
            endTime = endRaw?.let { parseTime(it, zone) } ?: now
            startTime = if (beginRaw != null) parseTime(beginRaw, zone) else when (rangePreset) { "week" -> now.minusDays(7); else -> now.toLocalDate().atStartOfDay(zone) }
        } catch (e: Exception) { return errorPayload("INVALID_TIME", e.message ?: "Invalid time format.") }
        if (!startTime.isBefore(endTime)) return errorPayload("INVALID_RANGE", "begin must be earlier than end.")
        val startMs = startTime.toInstant().toEpochMilli(); val endMs = endTime.toInstant().toEpochMilli()
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = context.packageManager; val launcherPackages = resolveLauncherPackages(pm)
        val foregroundMs = computeForegroundTime(usageStatsManager, startMs, endMs, launcherPackages)
        val sorted = foregroundMs.entries.filter { it.value > 0 }.sortedByDescending { it.value }
        val totalMs = sorted.sumOf { it.value }
        val apps = JSONArray()
        sorted.take(top).forEach { entry -> apps.put(JSONObject().put("package", entry.key).put("app_name", resolveAppName(pm, entry.key)).put("total_ms", entry.value).put("total_minutes", entry.value / 60000)) }
        return JSONObject().put("range", if (beginRaw != null || endRaw != null) "custom" else rangePreset).put("start", startTime.withNano(0).toString()).put("end", endTime.withNano(0).toString()).put("total_ms", totalMs).put("total_minutes", totalMs / 60000).put("apps", apps).toString()
    }
    private val lookbackMs = 12L * 60 * 60 * 1000
    @Suppress("DEPRECATION")
    private fun computeForegroundTime(usageStatsManager: UsageStatsManager, startMs: Long, endMs: Long, excludedPackages: Set<String>): Map<String, Long> {
        val foregroundMs = HashMap<String, Long>(); val events = usageStatsManager.queryEvents(startMs - lookbackMs, endMs); val event = UsageEvents.Event()
        var currentPkg: String? = null; var currentStart = 0L
        fun settle(until: Long) { val pkg = currentPkg; currentPkg = null; if (pkg == null || pkg in excludedPackages) return; val from = maxOf(currentStart, startMs); val duration = until - from; if (duration > 0) foregroundMs[pkg] = (foregroundMs[pkg] ?: 0L) + duration }
        while (events.hasNextEvent()) { events.getNextEvent(event); when (event.eventType) { UsageEvents.Event.MOVE_TO_FOREGROUND -> { if (event.packageName != currentPkg) { settle(event.timeStamp); currentPkg = event.packageName; currentStart = event.timeStamp } }; UsageEvents.Event.MOVE_TO_BACKGROUND -> { if (event.packageName == currentPkg) settle(event.timeStamp) }; UsageEvents.Event.SCREEN_NON_INTERACTIVE -> settle(event.timeStamp) } }; settle(endMs); return foregroundMs
    }
    private fun resolveLauncherPackages(pm: PackageManager): Set<String> { val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME); return runCatching { pm.queryIntentActivities(intent, 0).mapNotNull { it.activityInfo?.packageName }.toSet() }.getOrDefault(emptySet()) }
    private fun resolveAppName(pm: PackageManager, packageName: String) = runCatching { pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString() }.getOrDefault(packageName)

    private fun queryCalendar(params: JSONObject): String {
        val limit = params.optString("limit").toIntOrNull()?.coerceIn(1, 100) ?: params.optInt("limit", 20).coerceIn(1, 100)
        val query = params.optString("query").takeIf { it.isNotBlank() }
        val now = ZonedDateTime(); val zone = now.zone
        val beginRaw = params.optString("begin").takeIf { it.isNotBlank() }; val endRaw = params.optString("end").takeIf { it.isNotBlank() }
        val rangePreset = params.optString("range").takeIf { it.isNotBlank() } ?: "today"
        val startTime: ZonedDateTime; val endTime: ZonedDateTime
        try {
            startTime = if (beginRaw != null) parseTime(beginRaw, zone) else when (rangePreset) { "week" -> now.toLocalDate().atStartOfDay(zone).minusDays(now.dayOfWeek.value.toLong() - 1); "month" -> now.toLocalDate().withDayOfMonth(1).atStartOfDay(zone); else -> now.toLocalDate().atStartOfDay(zone) }
            endTime = if (endRaw != null) parseTime(endRaw, zone) else if (beginRaw != null) now else when (rangePreset) { "week" -> startTime.plusDays(7); "month" -> startTime.plusMonths(1); else -> now.toLocalDate().plusDays(1).atStartOfDay(zone) }
        } catch (e: Exception) { return errorPayload("INVALID_TIME", e.message ?: "Invalid time format.") }
        if (!startTime.isBefore(endTime)) return errorPayload("INVALID_RANGE", "begin must be earlier than end.")
        val startMs = startTime.toInstant().toEpochMilli(); val endMs = endTime.toInstant().toEpochMilli()
        val projection = arrayOf(CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE, CalendarContract.Instances.DESCRIPTION, CalendarContract.Instances.EVENT_LOCATION, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
        val selection = if (query != null) "${CalendarContract.Instances.TITLE} LIKE ? ESCAPE '\'" else null
        val selectionArgs = if (query != null) { val escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_"); arrayOf("%$escaped%") } else null
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().appendPath(startMs.toString()).appendPath(endMs.toString()).build()
        val events = JSONArray()
        context.contentResolver.query(uri, projection, selection, selectionArgs, "${CalendarContract.Instances.BEGIN} ASC")?.use { cursor ->
            var count = 0
            while (cursor.moveToNext() && count < limit) {
                val dtStart = cursor.getLong(4); val dtEnd = cursor.getLong(5); val allDay = cursor.getInt(6) == 1
                val obj = JSONObject().put("id", cursor.getLong(0)).put("title", cursor.getString(1) ?: "").put("description", cursor.getString(2) ?: "").put("location", cursor.getString(3) ?: "")
                if (allDay) { obj.put("start", Instant.ofEpochMilli(dtStart).atZone(ZoneOffset.UTC).toLocalDate().toString()); obj.put("end", if (dtEnd > 0) Instant.ofEpochMilli(dtEnd).atZone(ZoneOffset.UTC).toLocalDate().toString() else "") }
                else { obj.put("start", Instant.ofEpochMilli(dtStart).atZone(zone).withNano(0).toString()); obj.put("end", if (dtEnd > 0) Instant.ofEpochMilli(dtEnd).atZone(zone).withNano(0).toString() else "") }
                obj.put("all_day", allDay); obj.put("calendar", cursor.getString(7) ?: ""); events.put(obj); count++
            }
        }
        return JSONObject().put("range_start", startTime.withNano(0).toString()).put("range_end", endTime.withNano(0).toString()).put("count", events.length()).put("events", events).toString()
    }

    private fun createCalendarEvent(params: JSONObject): String {
        val title = params.optString("title").takeIf { it.isNotBlank() }; val startRaw = params.optString("start").takeIf { it.isNotBlank() }; val endRaw = params.optString("end").takeIf { it.isNotBlank() }; val allDay = params.optBoolean("all_day", false)
        if (title == null || startRaw == null) return errorPayload("MISSING_REQUIRED", "Both 'title' and 'start' are required.")
        val zone = ZoneId.systemDefault()
        val startTime: ZonedDateTime; val endTime: ZonedDateTime
        try { startTime = parseTime(startRaw, zone); endTime = if (endRaw != null) parseTime(endRaw, zone) else if (allDay) startTime.toLocalDate().plusDays(1).atStartOfDay(zone) else startTime.plusHours(1) } catch (e: Exception) { return errorPayload("INVALID_TIME", e.message ?: "Invalid time format.") }
        if (!startTime.isBefore(endTime)) return errorPayload("INVALID_RANGE", "end must be later than start.")
        val description = params.optString("description"); val location = params.optString("location"); val reminderMinutes = parseReminderMinutes(params.opt("reminders"))
        val eventStartMillis: Long; val eventEndMillis: Long; val eventTimeZone: String
        if (allDay) { val startDate = startTime.toLocalDate(); val endDate = endTime.toLocalDate(); if (!startDate.isBefore(endDate)) return errorPayload("INVALID_RANGE", "all-day event end date must be later than start date."); eventStartMillis = startDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(); eventEndMillis = endDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(); eventTimeZone = "UTC" } else { eventStartMillis = startTime.toInstant().toEpochMilli(); eventEndMillis = endTime.toInstant().toEpochMilli(); eventTimeZone = zone.id }
        val calendarId = getDefaultCalendarId() ?: return errorPayload("NO_CALENDAR", "No calendar account found on this device. Please add a calendar account first.")
        val values = ContentValues().apply { put(CalendarContract.Events.CALENDAR_ID, calendarId); put(CalendarContract.Events.TITLE, title); put(CalendarContract.Events.DESCRIPTION, description); put(CalendarContract.Events.EVENT_LOCATION, location); put(CalendarContract.Events.DTSTART, eventStartMillis); put(CalendarContract.Events.DTEND, eventEndMillis); put(CalendarContract.Events.EVENT_TIMEZONE, eventTimeZone); if (allDay) put(CalendarContract.Events.ALL_DAY, 1) }
        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) ?: return errorPayload("INSERT_FAILED", "Failed to insert calendar event.")
        val eventId = ContentUris.parseId(uri); val savedReminders = insertReminders(eventId, reminderMinutes)
        if (savedReminders.isNotEmpty()) { runCatching { context.contentResolver.update(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId), ContentValues().apply { put(CalendarContract.Events.HAS_ALARM, 1) }, null, null) } }
        val payload = JSONObject().put("success", true).put("event_id", eventId).put("title", title).put("start", startTime.withNano(0).toString()).put("end", endTime.withNano(0).toString()).put("all_day", allDay).put("location", location).put("reminders", JSONArray(savedReminders))
        if (savedReminders.size < reminderMinutes.size) payload.put("reminders_requested", JSONArray(reminderMinutes)).put("warning", "The event was created, but the calendar account rejected some reminders. Tell the user which reminders were actually saved.")
        return payload.toString()
    }
    private fun parseReminderMinutes(raw: Any?): List<Int> {
        if (raw == null || raw == JSONObject.NULL) return emptyList()
        val items: List<Any?> = when (raw) { is JSONArray -> (0 until raw.length()).map { raw.opt(it) }; else -> listOf(raw) }
        val minutes = LinkedHashSet<Int>()
        for (item in items) { val value = when (item) { is Number -> item.toDouble(); is String -> item.trim().toDoubleOrNull(); else -> null } ?: continue; if (value.isNaN() || value.isInfinite()) continue; minutes.add(Math.abs(value).coerceAtMost(40320.0).toInt()); if (minutes.size == 5) break }
        return minutes.toList()
    }
    private fun insertReminders(eventId: Long, minutes: List<Int>): List<Int> {
        if (minutes.isEmpty()) return emptyList()
        val saved = mutableListOf<Int>()
        for (minute in minutes) { val values = ContentValues().apply { put(CalendarContract.Reminders.EVENT_ID, eventId); put(CalendarContract.Reminders.MINUTES, minute); put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT) }; val inserted = runCatching { context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, values) }.getOrNull(); if (inserted != null) saved.add(minute) }
        return saved
    }
    private fun getDefaultCalendarId(): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val writableSelection = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ? AND ${CalendarContract.Calendars.SYNC_EVENTS} = 1"; val writableArgs = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        context.contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, "$writableSelection AND ${CalendarContract.Calendars.IS_PRIMARY} = 1", writableArgs, null)?.use { cursor -> if (cursor.moveToFirst()) return cursor.getLong(0) }
        context.contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, writableSelection, writableArgs, "${CalendarContract.Calendars.VISIBLE} DESC")?.use { cursor -> if (cursor.moveToFirst()) return cursor.getLong(0) }
        return null
    }
    private fun parseTime(raw: String, zone: ZoneId): ZonedDateTime {
        val text = raw.trim()
        text.toLongOrNull()?.let { return Instant.ofEpochMilli(it).atZone(zone) }
        runCatching { return OffsetDateTime.parse(text).atZoneSameInstant(zone) }; runCatching { return Instant.parse(text).atZone(zone) }; runCatching { return LocalDateTime.parse(text).atZone(zone) }; runCatching { return LocalDate.parse(text).atStartOfDay(zone) }
        error("Invalid time format: '$text'. Use ISO-8601 date/date-time or epoch milliseconds.")
    }
}