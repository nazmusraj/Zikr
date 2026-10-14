# Nūr Zikr

[![Android CI](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml/badge.svg)](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml)

An offline-first Android tasbih and spiritual activity tracker with Arabic, English, and Bengali content.

## Download the Android app

### [Download the latest Nūr Zikr APK](https://github.com/nazmusraj/Zikr/releases/latest/download/Nur-Zikr.apk)

Open the link on an Android device, download `Nur-Zikr.apk`, and tap the file to install it. Android may ask you to allow installs from your browser or file manager.

If a release has not been published yet, signed-in GitHub users can download the newest test build from the [latest successful Android CI run](https://github.com/nazmusraj/Zikr/actions/workflows/android-ci.yml?query=branch%3Amain) under **Artifacts → Nur-Zikr-test-APK**.

> Nūr Zikr works entirely offline and does not request network permission. Counts and preferences remain on the device.

## Features

- Tactile tasbih counter with sound and Android haptics
- Arabic, English, and Bengali zikr text
- Custom zikr entries and daily targets
- Daily, weekly, monthly, and yearly analytics
- Milestones, streaks, themes, and local backup export

## Developer guide

- [Build and test locally](docs/BUILDING.md)
- [Publish a signed GitHub release](docs/RELEASING.md)
- [Android application module](app/)

The repository automatically checks every change, stores an installable test APK for successful `main` builds, and publishes `Nur-Zikr.apk` when a version tag such as `v1.0.0` is pushed.
