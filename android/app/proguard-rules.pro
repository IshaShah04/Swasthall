# Keep ZegoUIKit and its signaling plugin
-keep class com.zegocloud.** { *; }
-keep class com.zego.** { *; }

# Keep Flutter Native Splash (to prevent flicker)
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }

# Keep Supabase/Postgrest classes
-keep class io.supabase.** { *; }

# Necessary for full-screen intent handling
-keep class android.support.v4.app.NotificationCompat$* { *; }
-keep class androidx.core.app.NotificationCompat$* { *; }