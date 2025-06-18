// lib/models/chat_messageai.dart

// An enum to differentiate message types for styling
enum MessageType { user, bot, error }

class ChatMessage {
  // text is no longer final, so we can update it during streaming
  String text;
  // messageType should be final. It's set once and doesn't change.
  final MessageType messageType;

  ChatMessage({
    required this.text,
    required this.messageType,
  });
}
