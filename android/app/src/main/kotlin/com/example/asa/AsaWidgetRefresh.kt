package com.example.asa

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

object AsaWidgetRefresh {
    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            AsaWidgetProvider::class.java,
            AsaWidgetStatsProvider::class.java,
            AsaWidgetTasksProvider::class.java,
        )
        providers.forEach { providerClass ->
            val component = ComponentName(context, providerClass)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return@forEach

            if (providerClass == AsaWidgetTasksProvider::class.java) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_task_list)
            }
            context.sendBroadcast(
                Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                    setComponent(component)
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                },
            )
        }
    }
}
