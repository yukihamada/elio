fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

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

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
