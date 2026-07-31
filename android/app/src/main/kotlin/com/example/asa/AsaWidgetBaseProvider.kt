package com.example.asa

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Shared logic for all ASA home screen widgets.
 *
 * Subclasses only need to provide a layout resource that contains the same
 * view IDs used here: `widget_root`, `widget_streak`, and `widget_active_tasks`.
 */
abstract class AsaWidgetBaseProvider(private val layoutResId: Int) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, layoutResId)
            try {
                views.renderWidget(context, widgetData)
            } catch (_: RuntimeException) {
                // A malformed preference must not prevent the launcher from
                // rendering the widget. Show a useful safe state instead.
                views.renderDisabled(context)
            }

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun RemoteViews.renderWidget(context: Context, widgetData: SharedPreferences) {
        val enabled = widgetData.safeBoolean("widget_enabled", true)
        if (!enabled) {
            renderDisabled(context)
            return
        }

        val mode = widgetData.safeString("widget_mode", MODE_ACTIVE_TASKS)
        val streak = widgetData.safeInt("streak", 1).coerceAtLeast(1)
        val activeTasks = widgetData.safeInt("active_tasks", 0).coerceAtLeast(0)
        val folderName = widgetData.safeString("last_folder", "")
            .trim()
            .ifEmpty { context.getString(R.string.widget_last_folder) }
            .take(MAX_FOLDER_NAME_LENGTH)

        val primaryText: String
        val secondaryText: String
        when (mode) {
            MODE_LAST_FOLDER -> {
                primaryText = folderName
                secondaryText = activeTasksText(context, activeTasks)
            }
            MODE_STREAK -> {
                primaryText = context.getString(R.string.widget_streak_format, streak)
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
            context.getString(R.string.widget_content_description, primaryText, secondaryText)
        )
    }

    private fun RemoteViews.renderDisabled(context: Context) {
        val disabled = context.getString(R.string.widget_disabled)
        setTextViewText(R.id.widget_streak, disabled)
        setTextViewText(R.id.widget_active_tasks, "")
        setContentDescription(R.id.widget_root, disabled)
    }

    private fun activeTasksText(context: Context, activeTasks: Int): String =
        context.resources.getQuantityString(
            R.plurals.widget_active_tasks,
            activeTasks,
            activeTasks
        )

    private fun SharedPreferences.safeBoolean(key: String, defaultValue: Boolean): Boolean =
        try {
            getBoolean(key, defaultValue)
        } catch (_: ClassCastException) {
            defaultValue
        }

    private fun SharedPreferences.safeInt(key: String, defaultValue: Int): Int =
        try {
            getInt(key, defaultValue)
        } catch (_: ClassCastException) {
            defaultValue
        }

    private fun SharedPreferences.safeString(key: String, defaultValue: String): String =
        try {
            getString(key, defaultValue) ?: defaultValue
        } catch (_: ClassCastException) {
            defaultValue
        }

    private companion object {
        const val MODE_ACTIVE_TASKS = "activeTasks"
        const val MODE_STREAK = "streak"
        const val MODE_LAST_FOLDER = "lastFolder"
        const val MAX_FOLDER_NAME_LENGTH = 80
    }
}
