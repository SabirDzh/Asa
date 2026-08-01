package com.example.asa

import android.content.Context
import android.content.SharedPreferences

/** Defensive access to the HomeWidget preference store used by RemoteViews. */
object AsaWidgetData {
    const val PREFERENCES = "HomeWidgetPreferences"
    const val TASKS_JSON = "widget_tasks_json"
    const val FOLDERS_JSON = "widget_folders_json"
    const val FOLDER_PREFIX = "widget_folder_"

    fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun selectedFolderId(context: Context, appWidgetId: Int): String? =
        preferences(context).getString("$FOLDER_PREFIX$appWidgetId", null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    fun setSelectedFolderId(context: Context, appWidgetId: Int, folderId: String?) {
        preferences(context).edit().apply {
            if (folderId.isNullOrBlank()) remove("$FOLDER_PREFIX$appWidgetId")
            else putString("$FOLDER_PREFIX$appWidgetId", folderId)
        }.apply()
    }

    fun removeWidget(context: Context, appWidgetId: Int) {
        preferences(context).edit().remove("$FOLDER_PREFIX$appWidgetId").apply()
    }
}
