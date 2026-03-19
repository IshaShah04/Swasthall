import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIAssistantService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Sanitise free-text before sending to AI (prevents prompt injection).
  static String _sanitise(String input) {
    String cleaned = input
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

    final String sanitisedInput = _sanitise(userInput);
    if (sanitisedInput.isEmpty) {
      return {"error": "Please describe your symptoms."};
    }

    final String lang = preferredLanguage == "ne-NP"
        ? "Nepali"
        : preferredLanguage == "hi-IN"
            ? "Hindi"
            : "English";

    final String systemPrompt = """
ROLE: Warm Healthcare Guide in Nepal. Respond in $lang.
TASK: Match symptoms to the DATABASE of doctors and labs provided. Output ONLY valid JSON.
SCHEMA: {
  "specialty": "string",
  "suggestion": "string",
  "estimates": [
    {
      "doctorName": "string",
      "hospital": "string",
      "address": "string",
      "consultationFee": "string",
      "otherCostsRange": "string"
    }
  ],
  "disclaimer": "string"
}
""";

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
          'systemPrompt': systemPrompt,
          'localDoctors': localDoctors,
          'labTests': labTests,
        },
      );

      final dynamic data = response.data;

      // Log full raw response for debugging
      debugPrint("AI RAW RESPONSE: $data");

      if (data == null) {
        return {"error": "Empty response from assistant."};
      }

      Map<String, dynamic> result;

      if (data is Map<String, dynamic>) {
        // Log detail field if present (from Edge Function error responses)
        if (data['detail'] != null) {
          debugPrint("AI DETAIL: ${data['detail']}");
        }
        if (data['error'] != null) {
          debugPrint("AI ERROR: ${data['error']} | DETAIL: ${data['detail']}");
          return {
            "error": data['error'].toString(),
            if (data['detail'] != null) "detail": data['detail'].toString(),
          };
        }
        result = data;
      } else if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['detail'] != null) {
          debugPrint("AI DETAIL: ${map['detail']}");
        }
        if (map['error'] != null) {
          debugPrint("AI ERROR: ${map['error']} | DETAIL: ${map['detail']}");
          return {
            "error": map['error'].toString(),
            if (map['detail'] != null) "detail": map['detail'].toString(),
          };
        }
        result = map;
      } else {
        debugPrint("AI UNEXPECTED TYPE: ${data.runtimeType} => $data");
        return {"error": "Invalid response format from assistant."};
      }

      // Re-attach doctor IDs locally from trusted source
      final estimates = result['estimates'];
      if (estimates is List) {
        _enrichEstimatesWithIds(estimates, localDoctors);
      }

      return result;
    } on FunctionException catch (e) {
      debugPrint("AI FunctionException: status=${e.status} details=${e.details} reason=${e.reasonPhrase}");
      return {
        "error": e.details?.toString() ??
            e.reasonPhrase ??
            "Assistant service unavailable.",
      };
    } catch (e, stack) {
      debugPrint("AI Exception: $e");
      debugPrint("AI Stack: $stack");
      return {"error": "Network error. Check your connection."};
    }
  }
}