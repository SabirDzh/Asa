package com.example.asa

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationGranted" ->
                    result.success(isNotificationGranted())
                "notificationsPermanentlyDenied" ->
                    result.success(isNotificationPermissionPermanentlyDenied())
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "isExactAlarmGranted" ->
                    result.success(isExactAlarmGranted())
                "openExactAlarmSettings" -> {
                    openExactAlarmSettings()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(null)
                }
                "isAutoStartAvailable" ->
                    result.success(isAutoStartAvailable())
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * True when the runtime notification permission has been granted.
     * On Android < 13 (API 32-) this always returns true because the
     * permission is granted at install time, not at runtime.
     */
    private fun isNotificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * True when the user can no longer be asked for the notification permission
     * through the system dialog (denied twice, or "don't ask again" was
     * selected). Such a user must be redirected to the system settings.
     */
    private fun isNotificationPermissionPermanentlyDenied(): Boolean {
        // POST_NOTIFICATIONS is a runtime permission only on Android 13+.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val granted =
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (granted) return false
        // Before the first request the rationale also reports false, but the
        // Dart side only asks after a request attempt has already failed, so a
        // denial here always means "the dialog will not be shown again".
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val requested = prefs.getBoolean(
            "flutter.notification_permission_requested",
            false,
        )
        return requested && !shouldShowRequestPermissionRationale(
            Manifest.permission.POST_NOTIFICATIONS,
        )
    }

    private fun openNotificationSettings() {
        val intent =
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // Some OEM launchers ignore the notification-settings intent; fall
            // back to the application details page.
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ),
                )
            } catch (_: Exception) {
                // No settings activity is available; nothing else we can do.
            }
        }
    }

    /**
     * True when exact alarm scheduling is granted.
     * On Android < 12 (API 31-) this always returns true.
     */
    private fun isExactAlarmGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName"),
                    ),
                )
            } catch (_: Exception) {
                openAppDetails()
            }
        }
    }

    /**
     * True when the app is exempt from battery optimization restrictions.
     * On Xiaomi/HyperOS this may still be insufficient without auto-start.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Opens the "Ignore battery optimization" system dialog for this app.
     */
    private fun requestIgnoreBatteryOptimizations() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            openBatterySettings()
        }
    }

    private fun openBatterySettings() {
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (_: Exception) {
            openAppDetails()
        }
    }

    /**
     * Checks whether the device exposes an auto-start settings page.
     * Xiaomi/HyperOS, Huawei, Oppo, Vivo are common examples that do.
     */
    private fun isAutoStartAvailable(): Boolean {
        val intent = autoStartIntent() ?: return false
        return packageManager.resolveActivity(intent, 0) != null
    }

    private fun openAutoStartSettings() {
        val intent = autoStartIntent() ?: return openAppDetails()
        try {
            startActivity(intent)
        } catch (_: Exception) {
            openAppDetails()
        }
    }

    /**
     * Returns the OEM-specific auto-start settings intent, or null when the
     * device does not expose one through a public action string.
     */
    private fun autoStartIntent(): Intent? {
        // Xiaomi / HyperOS
        try {
            val xiaomi = Intent()
            xiaomi.component = android.content.ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            )
            if (packageManager.resolveActivity(xiaomi, 0) != null) return xiaomi
        } catch (_: Exception) {}
        // Fallback: generic application details
        return null
    }

    private fun openAppDetails() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {}
    }

    companion object {
        private const val CHANNEL = "asa/notifications"
    }
}
