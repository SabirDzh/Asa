package com.example.asa

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class AsaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.asa_widget_layout).apply {
                val streak = widgetData.getInt("streak", 1)
                val activeTasks = widgetData.getInt("active_tasks", 0)

                val activeTasksText = when {
                    activeTasks == 0 -> context.getString(R.string.widget_active_tasks_zero)
                    activeTasks % 100 in 11..14 -> context.getString(R.string.widget_active_tasks_many, activeTasks)
                    activeTasks % 10 == 1 -> context.getString(R.string.widget_active_tasks_one)
                    activeTasks % 10 in 2..4 -> context.getString(R.string.widget_active_tasks_few, activeTasks)
                    else -> context.getString(R.string.widget_active_tasks_many, activeTasks)
                }

                setTextViewText(R.id.widget_streak, context.getString(R.string.widget_streak_format, streak))
                setTextViewText(R.id.widget_active_tasks, activeTasksText)

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
