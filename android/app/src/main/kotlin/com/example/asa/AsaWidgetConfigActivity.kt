package com.example.asa

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import org.json.JSONArray

/** Configures the folder filter independently for each widget instance. */
class AsaWidgetConfigActivity : Activity() {
    private data class FolderOption(val id: String?, val name: String)

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var options: List<FolderOption> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        options = loadFolderOptions()
        val names = options.map { it.name }
        val selectedId = AsaWidgetData.selectedFolderId(this, appWidgetId)
        val selectedIndex = options.indexOfFirst { it.id == selectedId }.coerceAtLeast(0)

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(32, 24, 32, 16)
        }
        content.addView(TextView(this).apply {
            text = getString(R.string.widget_choose_folder)
            textSize = 20f
            setPadding(0, 0, 0, 16)
        })
        val spinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@AsaWidgetConfigActivity,
                android.R.layout.simple_spinner_dropdown_item,
                names,
            )
            setSelection(selectedIndex)
        }
        content.addView(
            spinner,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        content.addView(Button(this).apply {
            text = getString(R.string.widget_save_folder)
            setOnClickListener {
                val selected = options.getOrNull(spinner.selectedItemPosition)
                AsaWidgetData.setSelectedFolderId(this@AsaWidgetConfigActivity, appWidgetId, selected?.id)
                requestWidgetUpdate()
                setResult(
                    RESULT_OK,
                    Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
                )
                finish()
            }
        })
        setContentView(content)
    }

    private fun loadFolderOptions(): List<FolderOption> {
        val result = mutableListOf(FolderOption(null, getString(R.string.widget_all_tasks)))
        val raw = AsaWidgetData.preferences(this)
            .getString(AsaWidgetData.FOLDERS_JSON, "[]")
            ?: "[]"
        val folders = runCatching { JSONArray(raw) }.getOrNull() ?: JSONArray()
        for (index in 0 until folders.length()) {
            val folder = folders.optJSONObject(index) ?: continue
            val id = folder.optString("id").trim()
            val name = folder.optString("name").trim()
            if (id.isEmpty() || name.isEmpty()) continue
            result += FolderOption(id, name.take(80))
        }
        return result
    }

    private fun requestWidgetUpdate() {
        val manager = AppWidgetManager.getInstance(this)
        val provider = manager.getAppWidgetInfo(appWidgetId)?.provider ?: return
        sendBroadcast(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                setComponent(provider)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            },
        )
        if (provider.className == AsaWidgetTasksProvider::class.java.name) {
            manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_list)
        }
    }
}
