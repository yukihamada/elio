fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac build

```sh
[bundle exec] fastlane mac build
```

Build macOS app (Mac Catalyst)

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Deploy macOS to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Deploy macOS to Mac App Store

----


## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Run all tests

### ios unit_test

```sh
[bundle exec] fastlane ios unit_test
```

Run unit tests only

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app (no signing)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Deploy to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Deploy to App Store

### ios sync_certificates

```sh
[bundle exec] fastlane ios sync_certificates
```

Sync certificates (Match)

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload metadata to App Store Connect

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots to App Store Connect

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture screenshots using snapshot

### ios frame_screenshots

```sh
[bundle exec] fastlane ios frame_screenshots
```

Add device frames and promotional text to screenshots

### ios create_app_store_screenshots

```sh
[bundle exec] fastlane ios create_app_store_screenshots
```

Create App Store screenshots (capture + frame)

### ios build_for_testing

```sh
[bundle exec] fastlane ios build_for_testing
```

Build test bundle for Firebase Test Lab

### ios firebase_test

```sh
[bundle exec] fastlane ios firebase_test
```

Run tests on Firebase Test Lab using Flank (parallel)

### ios firebase_test_device

```sh
[bundle exec] fastlane ios firebase_test_device
```

Run tests on Firebase Test Lab with specific device

### ios firebase_devices

```sh
[bundle exec] fastlane ios firebase_devices
```

List available iOS devices on Firebase Test Lab

### ios stats

```sh
[bundle exec] fastlane ios stats
```

Show app statistics and download info

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
