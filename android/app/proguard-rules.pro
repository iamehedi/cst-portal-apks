# ============================================================
# Firebase Cloud Messaging — prevent R8 from stripping token logic
# ============================================================
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }
-keep class com.google.android.gms.gcm.** { *; }
-keep class com.google.firebase.messaging.RemoteMessage { *; }
-keep class com.google.firebase.messaging.RemoteMessage$* { *; }

# Firebase Core (often pulled as dependency)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ============================================================
# Supabase client — prevent stripping of serializable models
# ============================================================
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Kotlin serialization (used by Supabase internally)
-keepattributes *Annotation*
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}
-keep class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**

# ============================================================
# OkHttp / OkIO (used by Supabase and Firebase HTTP calls)
# ============================================================
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-dontwarn okio.**
-keep class okio.** { *; }

# ============================================================
# General serialization safety
# ============================================================
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ============================================================
# url_launcher — prevent R8 from stripping intent resolution
# ============================================================
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# ============================================================
# flutter_local_notifications — prevent R8 from stripping callbacks
# ============================================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# ============================================================
# file_picker — prevent R8 from stripping platform channel
# ============================================================
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ============================================================
# shared_preferences
# ============================================================
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ============================================================
# package_info_plus
# ============================================================
-keep class dev.fluttercommunity.packageinfo.** { *; }
-dontwarn dev.fluttercommunity.packageinfo.**

# ============================================================
# Permission handler (if used)
# ============================================================
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**
