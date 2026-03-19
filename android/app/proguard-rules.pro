# ─────────────────────────────────────────────────────────────────────────────
# ZEGO UIKit + Express SDK
# Both package roots must be kept — zegocloud is the UIKit wrapper,
# im.zego is the underlying Express/ZIM native bridge.
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.zegocloud.** { *; }
-keep class com.zego.** { *; }
-keep class im.zego.** { *; }
-keepclassmembers class im.zego.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Firebase + Google Play Services (required for FCM offline call push)
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ─────────────────────────────────────────────────────────────────────────────
# Flutter local notifications (full-screen call alerts)
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Notification compatibility (AndroidX + support)
# ─────────────────────────────────────────────────────────────────────────────
-keep class androidx.core.app.NotificationCompat$* { *; }
-keep class android.support.v4.app.NotificationCompat$* { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Supabase / Postgrest / Realtime
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# ─────────────────────────────────────────────────────────────────────────────
# Kotlin reflection (needed by many plugins)
# ─────────────────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Lazy { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Home Widget + App Widgets
# ─────────────────────────────────────────────────────────────────────────────
-keep class es.antonborri.home_widget.** { *; }
-keep class com.raunak.swasthall.PatientWidgetProvider { *; }
-keep class com.raunak.swasthall.NurseWidgetProvider { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Flutter embedding (prevents R8 from stripping Flutter's native entrypoints)
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# General — suppress warnings for optional dependencies
# ─────────────────────────────────────────────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**