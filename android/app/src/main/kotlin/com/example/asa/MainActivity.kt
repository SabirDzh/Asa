package com.example.asa

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
                "notificationsPermanentlyDenied" ->
                    result.success(isNotificationPermissionPermanentlyDenied())
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
        return !shouldShowRequestPermissionRationale(
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

    companion object {
        private const val CHANNEL = "asa/notifications"
    }
}
