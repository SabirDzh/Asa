package com.example.asa

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class AsaWidgetTaskService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        AsaWidgetTaskFactory(
            applicationContext,
            intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1),
        )


}

private class AsaWidgetTaskFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private data class Task(val id: String, val title: String, val folderId: String?)

    private var tasks: List<Task> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val preferences = AsaWidgetData.preferences(context)
        val raw = preferences.getString(AsaWidgetData.TASKS_JSON, "[]") ?: "[]"
        val selectedFolderId = AsaWidgetData.selectedFolderId(context, appWidgetId)
        val parsed = runCatching { JSONArray(raw) }.getOrNull() ?: JSONArray()
        val result = mutableListOf<Task>()
        for (index in 0 until parsed.length()) {
            val item = parsed.optJSONObject(index) ?: continue
            val folderId = item.optString("folderId").takeIf { it.isNotEmpty() }
            if (selectedFolderId != null && folderId != selectedFolderId) continue
            val id = item.optString("id").trim()
            val title = item.optString("title").trim()
            if (id.isEmpty() || title.isEmpty()) continue
            result += Task(id, title.take(120), folderId)
        }
        tasks = result.take(20)
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews? {
        val task = tasks.getOrNull(position) ?: return null
        return RemoteViews(context.packageName, R.layout.widget_task_row).apply {
            setTextViewText(R.id.widget_task_title, task.title)
            setBoolean(R.id.widget_task_checkbox, "setChecked", false)
            setContentDescription(R.id.widget_task_row, task.title)
            setOnClickFillInIntent(
                R.id.widget_task_row,
                Intent().apply {
                    data = Uri.parse(
                        "asa://widget/complete?taskId=${Uri.encode(task.id)}",
                    )
                },
            )
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        tasks.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
