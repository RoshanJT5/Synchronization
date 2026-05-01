# Redmi Y2/S2 Compatibility Report

## Current Status

**APK File:**
- Location: `web/downloads/syncronization-app.apk`
- Size: 84.47 MB
- Last Built: 2026-04-30 22:09:28
- Website Link: ✅ Properly linked in `web/index.html` at `<a id="apk-download" href="downloads/syncronization-app.apk">`

## Redmi Y2/S2 Device Issue

**Device Specifications:**
- Redmi Y2/S2 runs **Android 5.1-6.0** (API 22-23)
- Current app requires **minSdkVersion = 24** (Android 7.0+)

**Result:** ❌ **App CANNOT BE INSTALLED on Redmi Y2/S2** - the device does not meet the minimum Android version requirement.

## Why We Cannot Support Redmi Y2/S2

The current minimum SDK requirement (API 24) is enforced by **React Native 0.81.0**, which is the version used in this project.

To support Redmi Y2 (API 22-23), we would need to:
1. Downgrade to React Native 0.72.x or earlier
2. This would lose critical security patches and modern features
3. WebRTC support becomes unreliable on older Android versions
4. Socket.IO compatibility becomes problematic

**Security & Stability Risk:** ❌ NOT RECOMMENDED

## Recommended Solutions

### Option 1: Upgrade Device (Recommended for Users)
- Redmi Y2/S2 devices are from 2018-2019
- Recommend users upgrade to Android 7.0+ devices (Redmi Note 5, Redmi 6, etc.)
- Most modern Android devices support the app

### Option 2: Create Legacy Build (Development Option)
- Maintain a separate build branch for React Native 0.72.x
- Would require significant testing and maintenance
- Not recommended due to security concerns

## Current Compatibility

- **Supported:** Android 7.0+ (API 24+)
- **Minimum Recommended:** Android 9.0+ (API 28+) for optimal performance
- **Works Well On:** Redmi Note 5+, Redmi 6+, Redmi 7+, and all modern Android devices

## Website Link Verification

✅ **Confirmed:** The APK download link on the website is correct and points to the latest build.

Users clicking "Install Android App" on the website will download the latest 84.47 MB APK built on 2026-04-30.

## Testing the App

To test if crashes are related to the app code (not device incompatibility):
1. Use an Android 7.0+ device
2. If crashes still occur, they are likely due to:
   - Network connectivity issues
   - Signaling server not running
   - Missing server URL configuration
   - WebRTC permission issues on older Android 7-8 devices

