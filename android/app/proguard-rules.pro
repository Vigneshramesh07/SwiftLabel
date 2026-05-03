# Flutter specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Stripe PushProvisioning - optional paid module, safe to ignore
-dontwarn com.stripe.android.pushProvisioning.**
-keep class com.stripe.android.pushProvisioning.** { *; }

# Google Play Core - optional, safe to ignore if not using deferred components
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
