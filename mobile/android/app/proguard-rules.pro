# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/Cellar/android-sdk/24.3.3/tools/proguard/proguard-android.txt
# You can edit the include path and order by changing the proguardFiles
# directive in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# React Native
-keep class com.facebook.react.bridge.CatalystInstanceImpl { *; }
-keep class com.facebook.react.bridge.WritableNativeMap { *; }
-keep class com.facebook.react.bridge.WritableNativeArray { *; }

# Vision Camera (v4/v5)
-keep class com.mrousavy.camera.** { *; }
-keep class com.mrousavy.camera.frameprocessors.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-keep class com.oney.WebRTCModule.** { *; }

# Nitro Modules (Required for VisionCamera v5)
-keep class com.margelo.nitro.** { *; }
-keep class com.swmansion.reanimated.** { *; }

# Ensure JNI classes are kept
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
