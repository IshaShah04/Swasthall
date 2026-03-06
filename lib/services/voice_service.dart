import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final FlutterTts _tts = FlutterTts();
  static const String _langKey = "preferred_language_code";

  // Configuration Constants
  static const String nepali = "ne-NP";
  static const String hindi = "hi-IN";
  static const String english = "en-US";

  String currentLanguage = english;
  bool _isInitialized = false;

  /// Initializes TTS settings
  Future<void> initTts() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    currentLanguage = prefs.getString(_langKey) ?? english;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers
        ],
      );
    }

    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _updateLanguageSettings(currentLanguage);
    
    _isInitialized = true;
  }

  /// RESTORED: Naming for compatibility with your existing screens
  Future<void> speakWithSavedLanguage(String text) async {
    if (text.isEmpty) return;
    try {
      await _tts.stop(); 
      await _updateLanguageSettings(currentLanguage);
      await _tts.speak(text);
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }

  /// RESTORED: Placeholder to stop errors in main.dart
  /// We don't need the "Kill Logic" anymore, so this just logs.
  void enableGreetingOnce() {
    debugPrint("Greeting enabled (Master Guard removed for better reliability).");
  }

  /// Internal helper to sync pitch and language
  Future<void> _updateLanguageSettings(String code) async {
    await _tts.setLanguage(code);
    await _tts.setPitch(code == english ? 1.1 : 1.0);
  }

  /// Updates language and persists it
  Future<void> setLanguage(String code) async {
    currentLanguage = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
    await _updateLanguageSettings(code);
  }

  /// Loads language from disk
  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    // Supporting both keys just in case
    currentLanguage = prefs.getString(_langKey) ?? prefs.getString('selected_language') ?? english;
    await _updateLanguageSettings(currentLanguage);
  }

  /// Immediately silences the app (Call in dispose)
  Future<void> stop() async {
    await _tts.stop();
  }

  void setHandlers({
    required Function onStart, 
    required Function onComplete, 
    required Function onError
  }) {
    _tts.setStartHandler(() => onStart());
    _tts.setCompletionHandler(() => onComplete());
    _tts.setErrorHandler((msg) => onError(msg));
  }
}