# Flutter Gizlet

`flutter_gizlet` builds release packages for the Gizlet Store from existing
Flutter applications. Develop and debug on your computer with `flutter run`.
Build the ARM64 `.gzl` in CI and publish it with the Gizlet Store workflow.
Players install from the Store in the Launcher.

## Build an app

Use Flutter **3.47.0** to build the initial release. On Apple Silicon, the upstream
AOT compiler runs through Rosetta. The package targets ARM64 Gizlet OS runtime 1.

Add `gizlet.toml` beside your app's `pubspec.yaml` and declare the ARM64 package:

```toml
id = "io.example.hello"
name = "Hello"
version = "0.1.0"
runtime = 1

[[packages]]
target = "aarch64-unknown-linux-gnu"
tier = "lite"
entry = "flutter-pi"
```

From the Flutter app directory:

```sh
flutter pub global activate flutter_gizlet
flutter pub global run flutter_gizlet build --arch=arm64 --cpu=generic --release
```

The command writes a `.gzl` under `build/gizlet/`. In GitHub Actions, upload that
file under the `gizlet-packages` artifact and call
[`gizlet/.github`'s Store release workflow](https://github.com/gizlet/.github#releasing-to-gizlet-store).
Give the package an icon and a description when preparing the Store listing.

The runner uses DRM/KMS. The D-pad sends Flutter arrow keys. A sends Enter and
B sends Escape, following the Launcher A/B swap setting. Use Flutter focus and
shortcuts so the same UI responds to a desktop keyboard. Native desktop
plugins need separate support in the embedded runner.

## Development and release

The Dart CLI is in `bin/` and `lib/`. `tool/build-runtime.sh` builds the ARM64
runner from a pinned flutter-pi commit with the adaptations under `native/`.
`tool/ci.sh` checks a real Flutter AOT build and verifies the resulting archive.
CI runs on the organization's ARM64 runner. The release workflow builds on
GitHub-hosted runners when `main` contains an unpublished package version.

The publishing job restores the credential from `secrets/pub.dev.enc.json`
using the organization's `SOPS_AGE_KEY`. The file contains Dart CLI OAuth
credentials for a pub.dev uploader and is encrypted with the age recipient
in `.sops.yaml`.
