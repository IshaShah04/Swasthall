import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final FlutterTts _tts = FlutterTts();

  static const String nepali = "ne-NP";
  static const String hindi = "hi-IN";
  static const String english = "en-US";

  String currentLanguage = english;

  Future<void> initTts() async {
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
    
    // --- SPEED TUNING ---
    // Increased to 0.6 for instant, snappy delivery.
    await _tts.setSpeechRate(0.6); 
    await _tts.setPitch(1.2); 
    await _tts.setVolume(1.0);
    await _tts.setLanguage(currentLanguage);

    // --- WEB-SPECIFIC VOICE SELECTION ---
    if (kIsWeb) {
      try {
        List<dynamic>? voices = await _tts.getVoices;
        if (voices != null) {
          // Priority: 1. Natural voices, 2. Google Female voices, 3. Microsoft Aria (Soft)
          final bestVoice = voices.firstWhere(
            (v) {
              final name = v["name"].toString().toLowerCase();
              return name.contains("natural") || 
                     (name.contains("google") && name.contains("female")) ||
                     name.contains("aria") ||
                     name.contains("soft");
            },
            orElse: () => voices.first,
          );

          await _tts.setVoice({
            "name": bestVoice["name"], 
            "locale": bestVoice["locale"]
          });
        }
        // Silent warm-up to prevent first-time lag
        await _tts.speak(""); 
      } catch (e) {
        debugPrint("Web Voice Selection Error: $e");
      }
    }
  }

  Future<void> speakWithSavedLanguage(String text) async {
    if (text.isEmpty) return;
    try {
      // Direct call - no extra setting overhead
      await _tts.speak(text);
    } catch (e) {
      debugPrint("TTS Speak Error: $e");
    }
  }

  Future<void> setLanguage(String code) async {
    currentLanguage = code;
    await _tts.setLanguage(code);
    
    // South Asian languages often sound better with a slightly lower pitch
    if (code == nepali || code == hindi) {
      await _tts.setPitch(1.1);
    } else {
      await _tts.setPitch(1.2);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}