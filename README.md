# Nūr Zikr

[![Android CI](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml/badge.svg)](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml)

An offline-first Android tasbih and spiritual activity tracker with Arabic, English, and Bengali content, optional Google sign-in, progress backup, and competitive leaderboards.

## Download the Android app

### [Download the latest Nūr Zikr APK](https://github.com/nazmusraj/Zikr/releases/latest/download/Nur-Zikr.apk)

Open the link on an Android device, download `Nur-Zikr.apk`, and tap the file to install it. Android may ask you to allow installs from your browser or file manager.

If a release has not been published yet, signed-in GitHub users can download the newest test build from the [latest successful Android CI run](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml?query=branch%3Amain) under **Artifacts → Nur-Zikr-test-APK**.

> Nūr Zikr works without an internet connection. Detailed history and preferences stay on the device; signed-in users sync compact progress totals to Supabase when a connection is available.

## Features

- Tactile tasbih counter with sound and Android haptics
- Arabic, English, and Bengali zikr text
- Custom zikr entries and daily targets
- Daily, weekly, monthly, and yearly analytics
- Google account creation and resumable progress backup
- Fair global leaderboards where only direct taps affect the score
- Private invite-code groups for competition with friends
- Milestones, streaks, themes, and local backup export

## Developer guide

- [Build and test locally](docs/BUILDING.md)
- [Publish a signed GitHub release](docs/RELEASING.md)
- [Enable Google sign-in (one-time owner setup)](docs/GOOGLE_SIGN_IN.md)
- [Supabase backend schema and sync model](supabase/README.md)
- [Android application module](app/)

The repository automatically checks every change, stores an installable test APK for successful `main` builds, and publishes `Nur-Zikr.apk` when a version tag such as `v1.1.0` is pushed.
