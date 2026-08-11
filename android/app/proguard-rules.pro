-keep class com.example.asa.** { *; }
-keep class io.flutter.** { *; }

# flutter_local_notifications persists its scheduled-notification cache with Gson
# and resolves icons through resource-name reflection. R8 must keep the plugin
# classes and the generic TypeToken signatures, otherwise cancel()/reschedule()
# fail at runtime with "Missing type parameter".
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Play Core is only used when dynamic feature modules are enabled. Flutter references it
# reflectively for deferred components, so it may be absent from normal builds.
-dontwarn com.google.android.play.core.**
