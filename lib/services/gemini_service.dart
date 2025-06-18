// lib/services/gemini_service.dart

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // Make sure this key is correct and has the Vertex AI API enabled in your Google Cloud project.
  static const String _apiKey =
      'AIzaSyBjmI0n3EAsHShLGL_JFIepy-GTVaAFS7Q'; // YOUR API KEY

  // Singleton pattern
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  // Initialize the GenerativeModel
  final GenerativeModel _model = GenerativeModel(
    // --- THIS IS THE FIX ---
    // Switched to the globally available and stable 'gemini-pro' model.
    model: 'gemini-pro',

    apiKey: _apiKey,
  );

  // Getter to access the model
  GenerativeModel get model => _model;

  // Legacy helper function (streaming in the UI is primary)
  Future<String?> generateText(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text;
    } catch (e) {
      print("GeminiService Error: $e");
      return "An error occurred while connecting to the AI.";
    }
  }
}
