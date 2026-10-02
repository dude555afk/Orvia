package com.dude555afk.orvia.scheduled

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.dude555afk.orvia.OrviaApplication

class ScheduledTaskReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val scheduler = (context.applicationContext as OrviaApplication).scheduledTasks
        if (intent.action == ScheduledTasks.FIRE) { val id = intent.data?.lastPathSegment ?: return; scheduler.fire(id, intent.getLongExtra("dueAt", 0)) } else if (intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, android.app.AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) { scheduler.rescheduleAll() }
    }
}
