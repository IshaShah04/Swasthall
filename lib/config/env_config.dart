// lib/config/env_config.dart
// SECURITY FIXED VERSION
//
// Uses --dart-define at build time instead of a bundled env.json file.
// Secrets are NEVER written to disk in the APK's flutter_assets folder.
//
// Build command example:
//   flutter build apk \
//     --dart-define=SUPABASE_URL=https://yourproject.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=eyJ... \
//     --dart-define=ZEGO_APP_ID=123456789 \
//     --dart-define=FDA_API_KEY=your_fda_key
//
// In CI/CD (GitHub Actions) store these as repository secrets and pass via env vars.

class EnvConfig {
  // ── Supabase ──────────────────────────────────────────────────────────────
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  // ── Zego (video/voice calls) ──────────────────────────────────────────────
  // Token-based auth is used via the zego-token edge function.
  // appSign has been removed from the client binary for security.
  static const zegoAppId =
      int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0);

  // ── FDA API (used in study_hub.dart) ─────────────────────────────────────
  static const fdaApiKey =
      String.fromEnvironment('FDA_API_KEY', defaultValue: '');

  // ── Google / Gemini ───────────────────────────────────────────────────────
  // Prefer calling Gemini via your Supabase edge functions — avoid putting
  // Gemini API keys in the client app directly.
  static const geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');


  // ── eSewa Mobile SDK (client-side, required by official SDK) ─────────────
  static const esewaSdkClientId =
      String.fromEnvironment('ESEWA_SDK_CLIENT_ID', defaultValue: '');

  // esewaSdkSecretId REMOVED for security — secret is now server-side
  // in the esewa-initiate edge function (Deno.env).

  static const esewaSdkEnvironment =
      String.fromEnvironment('ESEWA_SDK_ENVIRONMENT', defaultValue: 'test');

  // ── Khalti Flutter SDK (client-side public key only) ────────────────────
  static const khaltiPublicKey =
      String.fromEnvironment('KHALTI_PUBLIC_KEY', defaultValue: '');

  static const khaltiEnvironment =
      String.fromEnvironment('KHALTI_ENVIRONMENT', defaultValue: 'test');

  // ── Validation: call in main() before runApp ──────────────────────────────
  static void validate() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty)     missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    if (zegoAppId == 0)          missing.add('ZEGO_APP_ID');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required build config: ${missing.join(', ')}. '
        'Pass via --dart-define at build time.',
      );
    }
  }
}