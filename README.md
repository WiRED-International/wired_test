# wired_test

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## API environments

API selection is automatic; do not switch `.env` before building.

| Build mode | Default API |
| --- | --- |
| Debug | `http://10.0.2.2:3000` (Android emulator host) |
| Profile | `https://widm.wiredhealthresources.net/apiv2` |
| Release | `https://widm.wiredhealthresources.net/apiv2` |

Normal Android Studio debugging needs no extra arguments. For a physical device,
use a reachable development server with an explicit override:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000
flutter run --profile --dart-define=API_BASE_URL=https://staging.example.com/apiv2
```

Android Studio's additional Flutter run arguments can use the same
`--dart-define=API_BASE_URL=...` option. Restart/rebuild after changing it;
hot reload does not change compilation settings.

Debug overrides may use HTTP or HTTPS. Profile overrides require HTTPS and
reject localhost, loopback, and emulator addresses. Release URLs require HTTPS
and the approved host `widm.wiredhealthresources.net`; other hosts are rejected.
All modes reject empty/malformed overrides, embedded credentials, query strings,
and fragments. Trailing slashes are normalized.

Invalid configuration stops application startup with an exception; it never
silently falls back. Validation runs at startup, not as a build-time check.
The resolved URL overrides only `API_BASE_URL` during dotenv initialization;
other `.env` settings remain available. Existing API consumers need no changes.
Build-time defines and bundled environment values are not secrets.
