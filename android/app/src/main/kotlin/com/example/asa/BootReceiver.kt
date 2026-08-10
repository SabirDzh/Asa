package com.example.asa

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Marks that a device reboot occurred so the Flutter side can reschedule
 * all task reminders when the user next opens the app.
 *
 * On Android 14+ (HyperOS 3), background execution is heavily restricted,
 * so the receiver only persists a flag. The actual rescheduling happens
 * in the Flutter app's startup path, which already calls [NotificationService.syncTasks].
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        // Use the same file name as Flutter's shared_preferences plugin
        // so the Dart side can read the flag directly.
        context
            .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_BOOT_COMPLETED, true)
            .apply()
    }

    companion object {
        const val KEY_BOOT_COMPLETED = "flutter.asa_boot_completed"
    }
}
