import 'dart:convert';
import 'package:flutter/material.dart'; 
import 'package:http/http.dart' as http;
import '../config/env_config.dart';

class AIAssistantService {
  static Future<Map<String, dynamic>> getRecommendationAndCost({
    required String userInput,
    required List<Map<String, dynamic>> localDoctors,
    required List<Map<String, dynamic>> labTests,
    required String preferredLanguage,
  }) async {
    final String key = EnvConfig.geminiApiKey.trim();
    if (key.isEmpty) return {"error": "API Key not configured."};

    final String lang = (preferredLanguage == "ne-NP") ? "Nepali" : (preferredLanguage == "hi-IN") ? "Hindi" : "English";

    // Instructions: Force the model to skip conversational filler for low-bandwidth speed.
    final systemPrompt = """
      ROLE: Warm Healthcare Guide in Nepal. Respond in $lang.
      TASK: Match symptoms to DATABASE. Output ONLY valid JSON.
      SCHEMA: {
        "specialty": "string",
        "suggestion": "string",
        "estimates": [{"doctorName": "string", "hospital": "string", "address": "string", "consultationFee": "string", "otherCostsRange": "string", "doctorId": "string"}],
        "disclaimer": "string"
      }
    """;

    try {
      // 2026 STABLE PRODUCTION ENDPOINT
      // Using 'gemini-3-flash-preview' for best 2026 reasoning/speed balance.
      final String url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$key";

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{
              "text": "$systemPrompt\n\nDATABASE:\nDoctors: ${jsonEncode(localDoctors)}\nLabs: ${jsonEncode(labTests)}\n\nUSER INPUT: $userInput"
            }]
          }]
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['candidates'] == null || data['candidates'].isEmpty) {
          return {"error": "Assistant is resting. Try again."};
        }

        String text = data['candidates'][0]['content']['parts'][0]['text'];
        
        // REGEX EXTRACTION: Necessary because AI models in 2026 often 
        // include "thought signatures" or markdown wrappers.
        final RegExp jsonRegex = RegExp(r'\{[\s\S]*\}');
        final match = jsonRegex.stringMatch(text);
        
        if (match != null) {
          return jsonDecode(match);
        }
        return {"error": "Format error in response."};
      } else {
        // Detailed log for debugging 404/401/429
        debugPrint("API Error Detail: ${response.body}");
        return {"error": "Server status ${response.statusCode}"};
      }
    } catch (e) {
      debugPrint("Assistant Error: $e");
      return {"error": "Network too slow. Check your connection."};
    }
  }
}