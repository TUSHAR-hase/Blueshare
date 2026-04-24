# BlueShare

BlueShare is an Android-focused Flutter app for secure Bluetooth Classic file sharing with mesh-style distribution. It lets one device act as the master node, send files to connected phones, and monitor delivery progress across relay levels from a single dashboard.

## Highlights

- Bluetooth Classic device discovery and connection management
- Master/client node roles for controlled mesh distribution
- Secure transfers with shared-passkey authorization and AES-256 chunk encryption
- Transfer dashboard with live progress, relay depth, topology, and status tracking
- Transfer history view for completed sessions
- Exportable transfer logs for debugging or field reporting
- Background transfer support with foreground service integration
- Configurable retry, reconnect, backoff, and concurrency settings
- Riverpod-based state management and clean layered project structure

## Why BlueShare

BlueShare is designed for scenarios where internet access is limited or unavailable, but files still need to move reliably between nearby Android devices. Instead of a simple one-to-one Bluetooth sender, the app is structured around controlled multi-device delivery, transfer telemetry, and operational visibility.

## Core Flow

1. Turn on Bluetooth and make the receiver discoverable.
2. Scan for nearby devices from the home screen.
3. Connect BlueShare-enabled phones that share the same mesh passkey.
4. Switch the sending device to `MASTER` mode.
5. Pick one or more files and start a secure mesh distribution.
6. Track progress, relay depth, failures, retries, and delivery coverage in the transfer dashboard.

## Features

### Device and session management

- Nearby device scanning
- Connected, paired, and visible device summaries
- Discoverable mode trigger
- Theme toggle and persisted app preferences

### Mesh transfer controls

- Shared passkey configuration
- Parallel outgoing wave size tuning
- Chunk retry and control retry tuning
- Reconnect attempt and retry backoff tuning
- Master/client role switching

### Monitoring and auditability

- Live mesh transfer dashboard
- Device-level transfer rows with speed, progress, and status detail
- Relay level topology view
- Transfer history screen
- Transfer log export

## Security Model

BlueShare supports protected transfers using a shared mesh passkey:

- Transfer offers can be signed so receivers can verify authorization
- File chunks can be encrypted before transport
- Mesh settings are stored locally and applied to new transfers
- Devices using a different passkey are rejected for secure transfer flows

This project currently uses:

- Shared-secret payload signing
- AES-256 chunk encryption

## Tech Stack

- Flutter
- Dart
- Riverpod
- `shared_preferences`
- `permission_handler`
- `file_picker`
- `flutter_foreground_task`
- Custom local plugin: [`packages/bt_classic`](packages/bt_classic)

## Project Structure

```text
lib/
  app/                App shell, routes, theme
  core/               Constants and shared app config
  data/
    models/           Protocol and transport models
    repositories/     Repository implementations
    services/         Bluetooth, storage, crypto, history, background tasks
  domain/
    entities/         Core business entities
    repositories/     Repository contracts
  presentation/
    controllers/      Screen-facing application logic
    providers/        Riverpod providers
    screens/          UI screens
test/
  services/           Unit tests for crypto, chunking, and checksums
packages/
  bt_classic/         Local Bluetooth Classic plugin
```

## Android Permissions

The Android app declares permissions for:

- Bluetooth discovery, connection, and advertising
- Location access on older Android versions
- Foreground service and wake lock support
- Notifications
- Battery optimization bypass request for long-running transfers

See [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) for the current permission list.

## Supported Platforms

BlueShare is built with Flutter, but the actual transfer workflow is currently centered on Android because it depends on a local Bluetooth Classic plugin.

| Platform | Status |
| -------- | ------ |
| Android  | Supported |
| iOS      | Not supported for transfer workflow |
| Web      | Not supported for transfer workflow |
| Windows  | Flutter scaffold only |
| macOS    | Flutter scaffold only |
| Linux    | Flutter scaffold only |

## Getting Started

### Prerequisites

- Flutter SDK installed
- Dart SDK compatible with the Flutter version in this project
- Android Studio or VS Code with Flutter tooling
- At least one Android device with Bluetooth Classic support

### Install dependencies

```bash
flutter pub get
```

### Run the app

```bash
flutter run
```

### Run tests

```bash
flutter test
```

## Development Notes

- The app uses a layered architecture with `presentation`, `domain`, and `data` separation.
- Transfer state and settings are exposed through Riverpod providers.
- The transfer protocol currently includes messages such as offer, chunk, acknowledgements, completion, cancel, and mesh reporting.
- Background transfers are integrated through a foreground service so long-running sessions can continue more reliably on Android.

## Existing Test Coverage

Current unit tests focus on service-level behavior such as:

- Transfer payload signing and verification
- Secure transfer secret rotation
- File chunking behavior
- Checksum generation and validation

## Roadmap Ideas

- Add screenshots or screen recordings for the GitHub page
- Add integration tests for end-to-end device workflows
- Improve public release documentation for field setup
- Add CI for formatting, analysis, and tests
- Add a root `LICENSE` file before wider public distribution

## License

This repository currently does not include a root license file. Add one before publishing publicly if you want others to reuse or contribute with clear terms.
