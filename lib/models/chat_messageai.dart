// lib/models/chat_messageai.dart

import 'dart:typed_data';

// An enum to differentiate message types for styling
enum MessageType { user, bot, error }

class ChatMessage {
  // text is no longer final, so we can update it during streaming
  String text;

  // These properties are set once and should be final
  final MessageType messageType;
  final Uint8List?
      imageBytes; // <-- The '?' goes here to make the type nullable

  ChatMessage({
    required this.text,
    required this.messageType,
    this.imageBytes, // <-- In the constructor, it's just the name. No '?' needed.
  });
}
