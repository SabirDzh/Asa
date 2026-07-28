-keep class com.example.asa.** { *; }
-keep class io.flutter.** { *; }

# Play Core is only used when dynamic feature modules are enabled. Flutter references it
# reflectively for deferred components, so it may be absent from normal builds.
-dontwarn com.google.android.play.core.**
