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
            val views = RemoteViews(context.packageName, layoutResId).apply {
                val enabled = widgetData.getBoolean("widget_enabled", true)
                val mode = widgetData.getString("widget_mode", "streak")

                if (!enabled) {
                    setTextViewText(R.id.widget_streak, context.getString(R.string.widget_disabled))
                    setTextViewText(R.id.widget_active_tasks, "")
                } else {
                    when (mode) {
                        "activeTasks" -> renderActiveTasks(context, widgetData)
                        "lastFolder" -> renderLastFolder(context, widgetData)
                        else -> renderStreak(context, widgetData)
                    }
                }

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun RemoteViews.renderStreak(context: Context, widgetData: SharedPreferences) {
        val streak = widgetData.getInt("streak", 1)
        val activeTasks = widgetData.getInt("active_tasks", 0)

        setTextViewText(R.id.widget_streak, context.getString(R.string.widget_streak_format, streak))
        setTextViewText(R.id.widget_active_tasks, activeTasksText(context, activeTasks))
    }

    private fun RemoteViews.renderActiveTasks(context: Context, widgetData: SharedPreferences) {
        val activeTasks = widgetData.getInt("active_tasks", 0)

        setTextViewText(R.id.widget_streak, activeTasks.toString())
        setTextViewText(R.id.widget_active_tasks, activeTasksText(context, activeTasks))
    }

    private fun RemoteViews.renderLastFolder(context: Context, widgetData: SharedPreferences) {
        val folderName = widgetData.getString("last_folder", null)
            ?: context.getString(R.string.widget_last_folder)

        setTextViewText(R.id.widget_streak, folderName)
        setTextViewText(R.id.widget_active_tasks, "")
    }

    private fun activeTasksText(context: Context, activeTasks: Int): String {
        return when {
            activeTasks == 0 -> context.getString(R.string.widget_active_tasks_zero)
            activeTasks % 100 in 11..14 -> context.getString(R.string.widget_active_tasks_many, activeTasks)
            activeTasks % 10 == 1 -> context.getString(R.string.widget_active_tasks_one)
            activeTasks % 10 in 2..4 -> context.getString(R.string.widget_active_tasks_few, activeTasks)
            else -> context.getString(R.string.widget_active_tasks_many, activeTasks)
        }
    }
}
