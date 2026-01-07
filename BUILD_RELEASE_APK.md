# Production Release APK Build Instructions

## Prerequisites

1. **Java JDK 17+** installed
2. **Android SDK** with build tools
3. **Flutter SDK** configured
4. **Keystore** for signing (optional - uses debug keystore if not provided)

## Step 1: Create Signing Keystore (Optional)

If you want to use a custom keystore instead of debug keystore:

```bash
cd android
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias release-key
```

## Step 2: Configure Signing (Optional)

Create `android/key.properties` (copy from `android/key.properties.template`):

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=release-keystore.jks
```

**Note:** `storeFile` path is relative to `android/` directory.

**Note:** If `key.properties` doesn't exist, the build will use debug keystore automatically.

## Step 3: Clean Build

```bash
flutter clean
cd android
./gradlew clean
cd ..
```

## Step 4: Build Release APK

### Option A: Single APK (Recommended)
```bash
flutter build apk --release
```

### Option B: Split APKs by ABI (Smaller size)
```bash
flutter build apk --release --split-per-abi
```

### Option C: App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

## Output Location

- **Single APK:** `build/app/outputs/flutter-apk/app-release.apk`
- **Split APKs:** `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, etc.
- **App Bundle:** `build/app/outputs/bundle/release/app-release.aab`

## Verification Checklist

After building, verify on a real device:

- [ ] Install APK on clean device
- [ ] App launches without crashes
- [ ] All permissions requested correctly
- [ ] Foreground service starts
- [ ] Location tracking works in background
- [ ] Check-in/checkout flow works
- [ ] Timers (1-minute grace) work correctly
- [ ] Geofence entry/exit triggers correctly
- [ ] App survives device reboot
- [ ] Battery optimization disabled

## Configuration Summary

### AndroidManifest.xml
✅ All required permissions declared
✅ Foreground service configured
✅ Boot receiver registered
✅ Background location permission included

### build.gradle.kts
✅ Minification disabled (matches debug behavior)
✅ Resource shrinking disabled
✅ ProGuard rules included (safety net)
✅ Debug symbols enabled

### proguard-rules.pro
✅ All app classes preserved
✅ All services preserved
✅ All timers/handlers preserved
✅ All Flutter/Dart classes preserved
✅ Logging preserved
✅ No obfuscation (matches debug)

## Troubleshooting

### Build fails with signing error
- Ensure `key.properties` exists OR remove it to use debug keystore
- Verify keystore path is correct
- Check passwords are correct

### APK behaves differently than debug
- Verify minification is disabled in `build.gradle.kts`
- Check ProGuard rules are applied
- Ensure all permissions are granted on device

### Location tracking stops in release
- Verify battery optimization is disabled
- Check foreground service notification appears
- Ensure background location permission granted

### Timers don't work
- Verify ProGuard rules preserve Handler/Runnable
- Check logs for timer-related errors
- Ensure app is not killed by system

