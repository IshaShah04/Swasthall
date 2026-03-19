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
//     --dart-define=ZEGO_APP_SIGN=abc123... \
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
  static const zegoAppId =
      int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0);

  static const zegoAppSign =
      String.fromEnvironment('ZEGO_APP_SIGN', defaultValue: '');

  // ── FDA API (used in study_hub.dart) ─────────────────────────────────────
  static const fdaApiKey =
      String.fromEnvironment('FDA_API_KEY', defaultValue: '');

  // ── Google / Gemini ───────────────────────────────────────────────────────
  // Prefer calling Gemini via your Supabase edge functions — avoid putting
  // Gemini API keys in the client app directly.
  static const geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // ── Validation: call in main() before runApp ──────────────────────────────
  static void validate() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty)     missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    if (zegoAppId == 0)          missing.add('ZEGO_APP_ID');
    if (zegoAppSign.isEmpty)     missing.add('ZEGO_APP_SIGN');

    assert(
      missing.isEmpty,
      'Missing required build config: ${missing.join(', ')}. '
      'Pass via --dart-define at build time.',
    );
  }
}