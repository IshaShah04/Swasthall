class EnvConfig {
  EnvConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String googleVisionApiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY', defaultValue: '');
  static const String fdaApiKey = String.fromEnvironment('FDA_API_KEY', defaultValue: '');
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // ZEGO Core
  static const int zegoAppId = int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0);
  static const String zegoAppSign = String.fromEnvironment('ZEGO_APP_SIGN', defaultValue: '');

  // NEW: Needed for WhatsApp-style background ringing
  static const String fcmServerKey = String.fromEnvironment('FCM_SERVER_KEY', defaultValue: '');
}