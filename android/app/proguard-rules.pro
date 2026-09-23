# App-specific R8 rules. Flutter and plugins provide their consumer rules.

# Security Hardening & Obfuscation
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable

# Strip Android debug logs in release builds to prevent information leakage
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Preserve Flutter engine & Security channel methods
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve MainActivity
-keep class com.invetstecur.stagiaire.MainActivity { *; }

# Suppress R8 missing class warnings for Play Core deferred components
-dontwarn com.google.android.play.core.**
