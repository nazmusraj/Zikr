# Publishing an APK on GitHub

The release workflow builds a signed APK and attaches it to a GitHub Release as `Nur-Zikr.apk`. The permanent README download link always resolves to the newest release.

## One-time signing setup

Create a release keystore and keep it somewhere secure:

```bash
keytool -genkeypair -v -keystore nur-zikr-release.jks -alias nur-zikr -keyalg RSA -keysize 2048 -validity 10000
```

Convert the keystore to a single-line Base64 value:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("nur-zikr-release.jks"))
```

In the GitHub repository, open **Settings → Secrets and variables → Actions** and add these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore contents |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias, such as `nur-zikr` |
| `ANDROID_KEY_PASSWORD` | Key password |

Never commit the keystore or passwords. Preserve the keystore securely: future APK updates must be signed with the same key.

## Publish a version

Update `versionCode` and `versionName` in `app/build.gradle.kts`, commit the change, then push a matching tag:

```bash
git tag v1.0.0
git push origin main v1.0.0
```

GitHub Actions will validate the app, build and verify the signed release APK, create release notes, and attach `Nur-Zikr.apk` automatically.
