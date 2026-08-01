# Android interactive widgets

## Goal
Upgrade ASA Android widgets from static counters to compatible RemoteViews widgets that can show tasks, complete tasks, open folders, and create tasks.

## UX by size/type
- Small summary widget: streak, active task count, add button, open app.
- Medium task widget: compact active-task list, completion action, add button, selected-folder label.
- Large task widget: larger active-task list, selected-folder label, completion action, add button, folder/app deep-link actions.
- Each configured widget instance stores its selected folder independently.

## Architecture
1. Flutter serializes a compact bounded task/folder payload into HomeWidgetPreferences; do not send full task info blocks or unbounded JSON.
2. Android uses RemoteViewsService/RemoteViewsFactory for collection lists.
3. List item actions use home_widget interactivity callback in the background so taps do not launch the full Flutter UI.
4. Add/folder actions use HomeWidgetLaunchIntent deep links and are handled by Flutter after app startup/resume.
5. Widget configuration activity stores folder ID by appWidgetId and returns RESULT_OK.
6. Use explicit Android PendingIntent mutability supplied by home_widget; internal RemoteViewsService is protected with BIND_REMOTEVIEWS and exported=false.

## Compatibility constraints
- Keep existing providers registered and retain static summary behavior.
- Use AppWidget APIs available from the project minSdk; guard newer options when needed.
- Keep each widget payload small (bounded task list and folder list).
- Never trust widget URI/task IDs without validating against stored JSON/provider data.
- Native widget action must update widget data best-effort and not crash the launcher.
- Preserve existing Flutter/home_widget tests and add payload/callback tests.
