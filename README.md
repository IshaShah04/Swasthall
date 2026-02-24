# health_department

A new Flutter project.

## Environment Setup

This app requires environment variables for API keys and secrets. Create an `env.json` file in the project root using `env.example.json` as a template:

```bash
cp env.example.json env.json
# Edit env.json with your actual credentials
```

The app reads these values at compile time via `--dart-define-from-file=env.json`. The VS Code launch configuration includes this automatically. For CLI runs:

```bash
flutter run --dart-define-from-file=env.json
flutter build web --dart-define-from-file=env.json
```

**Note:** `env.json` is gitignored. Never commit it or `google-services.json`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
