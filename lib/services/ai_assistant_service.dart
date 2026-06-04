import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIAssistantService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Sanitise free-text before sending to AI.
  /// This is not a full medical-safety filter; the Edge Function still owns
  /// the real system prompt and output rules.
  static String _sanitise(String input) {
    final cleaned = input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('\\', '')
        .trim();
    return cleaned.length > 500 ? cleaned.substring(0, 500) : cleaned;
  }

  /// After AI responds, look up the real doctor ID from the local list
  /// by matching on the doctor name. AI never controls which ID is used.
  static void _enrichEstimatesWithIds(
    List<dynamic> estimates,
    List<Map<String, dynamic>> localDoctors,
  ) {
    for (final estimate in estimates) {
      if (estimate is! Map) continue;
      final aiName =
          (estimate['doctorName'] ?? '').toString().toLowerCase().trim();
      if (aiName.isEmpty) continue;

      final match = localDoctors.firstWhere(
        (d) => (d['name'] ?? '').toString().toLowerCase().trim() == aiName,
        orElse: () => {},
      );

      if (match.isNotEmpty && match['id'] != null) {
        estimate['doctorId'] = match['id'].toString();
      }
    }
  }

  static Future<Map<String, dynamic>> getRecommendationAndCost({
    required String userInput,
    required List<Map<String, dynamic>> localDoctors,
    required List<Map<String, dynamic>> labTests,
    required String preferredLanguage,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      return {"error": "Please log in to use the AI assistant."};
    }

    final sanitisedInput = _sanitise(userInput);
    if (sanitisedInput.isEmpty) {
      return {"error": "Please describe your symptoms."};
    }

    final String lang = preferredLanguage == "ne-NP"
        ? "Nepali"
        : preferredLanguage == "hi-IN"
            ? "Hindi"
            : "English";

    try {
      final response = await _supabase.functions.invoke(
        'ai-proxy',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'userInput': sanitisedInput,
          'preferredLanguage': preferredLanguage,
          'languageLabel': lang,
          'promptMode': 'triage',
          'localDoctors': localDoctors,
          'labTests': labTests,
        },
      );

      final data = response.data;
      if (data == null) {
        return {"error": "Empty response from assistant."};
      }

      late final Map<String, dynamic> result;
      if (data is Map<String, dynamic>) {
        result = data;
      } else if (data is Map) {
        result = Map<String, dynamic>.from(data);
      } else {
        if (kDebugMode) {
          debugPrint('AI service returned unexpected type: ${data.runtimeType}');
        }
        return {"error": "Invalid response format from assistant."};
      }

      if (result['error'] != null) {
        if (kDebugMode) {
          debugPrint('AI service returned error: ${result['error']}');
        }
        return {"error": "Assistant service unavailable. Please try again."};
      }

      final estimates = result['estimates'];
      if (estimates is List) {
        _enrichEstimatesWithIds(estimates, localDoctors);
      }

      return result;
    } on FunctionException catch (e) {
      if (kDebugMode) {
        debugPrint('AI FunctionException status=${e.status} reason=${e.reasonPhrase}');
      }
      return {"error": "Assistant service unavailable. Please try again."};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI request failed: ${e.runtimeType}');
      }
      return {"error": "Network error. Check your connection."};
    }
  }
}
