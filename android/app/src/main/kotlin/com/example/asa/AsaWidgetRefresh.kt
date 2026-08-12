package com.example.asa

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

object AsaWidgetRefresh {
    fun refreshAll(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val providers = listOf(
            AsaWidgetProvider::class.java,
            AsaWidgetStatsProvider::class.java,
            AsaWidgetTasksProvider::class.java,
        )
        providers.forEach { providerClass ->
            val component = ComponentName(appContext, providerClass)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return@forEach

            if (providerClass == AsaWidgetTasksProvider::class.java) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_task_list)
            }
            appContext.sendBroadcast(
                Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                    setComponent(component)
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                },
            )
        }
    }
}
