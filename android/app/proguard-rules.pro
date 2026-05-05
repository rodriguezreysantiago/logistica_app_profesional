# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Mantener nombres de clases para reflection
-keepattributes *Annotation*
-keepattributes Signature

# Flutter referencia clases de Play Core para deferred components (no las usamos).
-dontwarn com.google.android.play.core.**

# ML Kit text recognition incluye modelos de idiomas opcionales (chino,
# japonés, coreano, devanagari) que no descargamos. Son referencias muertas.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
