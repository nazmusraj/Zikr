# Building Nūr Zikr

## Requirements

- JDK 17
- Android SDK 35

## Build an installable test APK

On Windows:

```powershell
.\scripts\package-debug.ps1
```

Or use Gradle directly on any platform:

```bash
./gradlew assembleDebug
```

The helper script places the user-friendly APK at `dist/Nur-Zikr-test.apk`. Gradle's original output remains at `app/build/outputs/apk/debug/app-debug.apk`.

## Run validation

```bash
./gradlew assembleDebug lintDebug
```

The app interface lives in `app/src/main/assets/index.html`. The Android WebView host and native haptic bridge live in `app/src/main/java/com/nurzikr/tasbih/MainActivity.kt`.
