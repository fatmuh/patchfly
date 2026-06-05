# Patchfly SDK proguard rules.
# These are applied to the consumer app when it's built in release mode.

# Keep our Kotlin classes
-keep class dev.patchfly.** { *; }

# Keep Flutter engine classes (we use reflection on them)
-keep class io.flutter.embedding.engine.loader.** { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.engine.dart.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.util.** { *; }

# Keep methods that are called via reflection
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
