package com.example.asa

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Shared rendering and action wiring for ASA widgets. */
abstract class AsaWidgetBaseProvider(private val layoutResId: Int) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, layoutResId)
            try {
                views.renderWidget(context, widgetData, widgetId)
            } catch (_: RuntimeException) {
                views.renderDisabled(context)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { AsaWidgetData.removeWidget(context, it) }
        super.onDeleted(context, appWidgetIds)
    }

    private fun RemoteViews.renderWidget(
        context: Context,
        widgetData: SharedPreferences,
        widgetId: Int,
    ) {
        val enabled = widgetData.safeBoolean("widget_enabled", true)
        if (!enabled) {
            renderDisabled(context)
            return
        }

        val mode = widgetData.safeString("widget_mode", MODE_ACTIVE_TASKS)
        val streak = widgetData.safeInt("streak", 1).coerceAtLeast(1)
        val activeTasks = widgetData.safeInt("active_tasks", 0).coerceAtLeast(0)
        val folderName = selectedFolderName(context, widgetData, widgetId)

        val primaryText: String
        val secondaryText: String
        when (mode) {
            MODE_LAST_FOLDER -> {
                primaryText = folderName.ifEmpty {
                    context.getString(R.string.widget_last_folder)
                }
                secondaryText = activeTasksText(context, activeTasks)
            }
            else -> {
                primaryText = activeTasksText(context, activeTasks)
                secondaryText = context.getString(R.string.widget_streak_format, streak)
            }
        }

        setTextViewText(R.id.widget_streak, primaryText)
        setTextViewText(R.id.widget_active_tasks, secondaryText)
        setContentDescription(
            R.id.widget_root,
            context.getString(R.string.widget_content_description, primaryText, secondaryText),
        )

        val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        setOnClickPendingIntent(R.id.widget_root, openApp)

        val addIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("asa://widget/add"),
        )
        setOnClickPendingIntent(R.id.widget_add, addIntent)

        if (layoutResId == R.layout.widget_tasks_layout) {
            val folderId = AsaWidgetData.selectedFolderId(context, widgetId)
            val folderName = selectedFolderName(context, widgetData, widgetId)
            setTextViewText(
                R.id.widget_folder_label,
                folderName.ifEmpty { context.getString(R.string.widget_all_tasks) },
            )
            val folderIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("asa://widget/folder?folderId=${Uri.encode(folderId ?: "")}"),
            )
            setOnClickPendingIntent(R.id.widget_folder_label, folderIntent)

            val serviceIntent = Intent(context, AsaWidgetTaskService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = Uri.parse("asa://widget/tasks/$widgetId")
            }
            setRemoteAdapter(widgetId, R.id.widget_task_list, serviceIntent)
            setEmptyView(R.id.widget_task_list, R.id.widget_empty)
            setPendingIntentTemplate(
                R.id.widget_task_list,
                completionPendingIntent(context),
            )
        }
    }

    private fun completionPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        // On API 23–30 omitting mutability flags preserves the mutable
        // PendingIntent behavior required for collection fill-in intents.
        // API 31+ requires FLAG_MUTABLE explicitly.
        return PendingIntent.getBroadcast(context, 7001, intent, flags)
    }

    private fun selectedFolderName(
        context: Context,
        widgetData: SharedPreferences,
        widgetId: Int,
    ): String {
        val folderId = AsaWidgetData.selectedFolderId(context, widgetId) ?: return ""
        val raw = widgetData.getString(AsaWidgetData.FOLDERS_JSON, "[]") ?: "[]"
        val folders = runCatching { org.json.JSONArray(raw) }.getOrNull() ?: return ""
        for (index in 0 until folders.length()) {
            val folder = folders.optJSONObject(index) ?: continue
            if (folder.optString("id") == folderId) return folder.optString("name").take(80)
        }
        return ""
    }

    private fun RemoteViews.renderDisabled(context: Context) {
        setTextViewText(R.id.widget_streak, context.getString(R.string.widget_disabled))
        setTextViewText(R.id.widget_active_tasks, "")
        setContentDescription(R.id.widget_root, context.getString(R.string.widget_disabled))
    }

    private fun activeTasksText(context: Context, activeTasks: Int): String =
        context.resources.getQuantityString(R.plurals.widget_active_tasks, activeTasks, activeTasks)

    private fun SharedPreferences.safeBoolean(key: String, defaultValue: Boolean): Boolean =
        try { getBoolean(key, defaultValue) } catch (_: ClassCastException) { defaultValue }

    private fun SharedPreferences.safeInt(key: String, defaultValue: Int): Int =
        try { getInt(key, defaultValue) } catch (_: ClassCastException) { defaultValue }

    private fun SharedPreferences.safeString(key: String, defaultValue: String): String =
        try { getString(key, defaultValue) ?: defaultValue } catch (_: ClassCastException) { defaultValue }

    private companion object {
        const val MODE_ACTIVE_TASKS = "activeTasks"
        const val MODE_LAST_FOLDER = "lastFolder"
    }
}
