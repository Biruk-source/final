//**File: `lib/screens/widgets/ai_chat_panel.dart`**

import 'dart:typed_data';
import 'dart:ui';
import 'package:animate_do/animate_do.dart';
import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:speech_to_text/speech_to_text.dart';

import 'package:my_app1/models/chat_messageai.dart';
import 'package:my_app1/models/worker.dart';
import 'package:my_app1/services/ai_chat_service.dart';
import 'package:my_app1/services/firebase_service.dart';
import 'package:my_app1/screens/worker_detail_screen.dart';

class AiChatPanel extends StatefulWidget {
  final VoidCallback onClose;
  final AiChatService aiChatService;

  const AiChatPanel({
    super.key,
    required this.onClose,
    required this.aiChatService,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseService _firebaseService = FirebaseService();

  // **FIXED 2: The class name from the package is just SpeechToText**
  final SpeechToText _speech = SpeechToText();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  
  // State for holding image data and its type
  Uint8List? _pickedImageBytes;
  String? _pickedImageMimeType;

  static const List<String> _suggestedPrompts = [
    "Find me a plumber near me",
    "Who is the highest-rated electrician?",
    "What's the price for a carpenter?",
    "Show me all available cleaners",
  ];

  @override
  void initState() {
    super.initState();
    _initializeSpeechRecognizer();
    _messages.add(
      ChatMessage(
        text: "Hello! I'm ready to help. Ask me anything about our professionals.",
        messageType: MessageType.bot,
      ),
    );
  }

  Future<void> _initializeSpeechRecognizer() async {
    await _speech.initialize(
      onStatus: (status) {
        if (mounted) setState(() => _isListening = _speech.isListening);
      },
      onError: (errorNotification) {
        print('Speech recognition error: $errorNotification');
        if (mounted) setState(() => _isListening = false);
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _sendMessage({String? prefilledText}) async {
    if (_isListening) {
      await _speech.stop();
      if(mounted) setState(() => _isListening = false);
    }
    
    final text = prefilledText ?? _textController.text.trim();
    if (text.isEmpty && _pickedImageBytes == null) return;

    FocusScope.of(context).unfocus();
    final userMessage = ChatMessage(
      text: text,
      messageType: MessageType.user,
      imageBytes: _pickedImageBytes,
    );
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    final content = _buildContent(text, _pickedImageBytes, _pickedImageMimeType);
    _textController.clear();
    setState(() {
      _pickedImageBytes = null;
      _pickedImageMimeType = null;
    });
    _scrollToBottom();

    try {
      final botMessage = ChatMessage(text: "", messageType: MessageType.bot);
      setState(() => _messages.add(botMessage));

      // **FIXED 3: Call the method that accepts a Content object**
      final stream = widget.aiChatService.sendMessageStream(content);

      await for (final chunk in stream) {
        if (chunk.text != null) {
          setState(() {
            _messages.last.text += chunk.text!;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      print("Gemini Stream Error: $e");
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          text: "Sorry, an error occurred: ${e.toString()}",
          messageType: MessageType.error,
        ));
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // **IMPROVEMENT 1: Make image handling more robust by using MIME type**
  Content _buildContent(String text, Uint8List? imageBytes, String? mimeType) {
    if (imageBytes != null && mimeType != null) {
      return Content.multi([
        TextPart(text.isEmpty ? "Analyze this image for a home repair app." : text),
        DataPart(mimeType, imageBytes),
      ]);
    } else {
      return Content.text(text);
    }
  }

  Future<void> _pickImage() async {
    if (await Permission.photos.request().isGranted) {
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (mounted) {
          setState(() {
            _pickedImageBytes = bytes;
            // **IMPROVEMENT 2: Store the MIME type of the picked image**
            _pickedImageMimeType = pickedFile.mimeType ?? 'image/jpeg'; // Fallback to jpeg
          });
        }
      }
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if(mounted) setState(() => _isListening = false);
    } else {
      final hasPermission = await _requestMicPermission();
      if (hasPermission) {
        await _speech.listen(
          onResult: (result) {
            if (mounted) {
              _textController.text = result.recognizedWords;
              _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
            }
          },
        );
         if(mounted) setState(() => _isListening = true);
      }
    }
  }
  
  Future<bool> _requestMicPermission() async {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission is required to use voice input.")),
        );
        return false;
      }
  }

  void _onMarkdownTapLink(String text, String? href, String title) async {
    if (href != null && href.startsWith('worker://')) {
      final workerId = href.replaceFirst('worker://', '');
      final Worker? worker = await _firebaseService.getWorkerById(workerId);
      if (worker != null && mounted) {
        widget.onClose();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => WorkerDetailScreen(worker: worker),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: Container(
          width: 400,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withOpacity(0.85),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
            border:
                Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 25,
                  offset: const Offset(-5, 5))
            ],
          ),
          child: Column(
            children: [
              _buildHeader(theme),
              Expanded(
                child: _messages.length <= 1
                    ? _buildSuggestedPrompts()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index < _messages.length) {
                            return _buildMessageBubble(_messages[index], theme);
                          } else {
                            return _buildTypingIndicator(theme);
                          }
                        },
                      ),
              ),
              _buildTextInput(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Text("AI Command Center",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: widget.onClose,
            tooltip: "Close",
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedPrompts() {
    return FadeIn(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _suggestedPrompts
                .map((prompt) => ActionChip(
                      avatar: Icon(Icons.quickreply_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.secondary),
                      label: Text(prompt),
                      onPressed: () => _sendMessage(prefilledText: prompt),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    final isUser = message.messageType == MessageType.user;
    final isError = message.messageType == MessageType.error;
    return FadeInUp(
      from: 20,
      duration: const Duration(milliseconds: 400),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : (isError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surface),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
              bottomRight: isUser ? Radius.zero : const Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.imageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(message.imageBytes!, fit: BoxFit.cover),
                  ),
                ),
              if (message.text.isNotEmpty)
                MarkdownBody(
                  data: message.text,
                  selectable: true,
                  onTapLink: _onMarkdownTapLink,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium?.copyWith(
                        color: isUser
                            ? theme.colorScheme.onPrimary
                            : (isError
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onSurface)),
                    code: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: GoogleFonts.firaCode().fontFamily,
                        backgroundColor:
                            theme.colorScheme.onSurface.withOpacity(0.1)),
                    a: TextStyle(
                      color: isUser ? Colors.yellowAccent : theme.colorScheme.secondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
                  3,
                  (index) => FadeIn(
                        delay: Duration(milliseconds: 200 * index),
                        child: Bounce(
                          infinite: true,
                          delay: Duration(milliseconds: 200 * index),
                          child: CircleAvatar(
                              radius: 4,
                              backgroundColor:
                                  theme.iconTheme.color?.withOpacity(0.4)),
                        ),
                      ))
              .expand((widget) => [widget, const SizedBox(width: 6)])
              .toList()
            ..removeLast(),
        ),
      ),
    );
  }

  Widget _buildTextInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_pickedImageBytes != null) _buildImagePreview(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: _isLoading ? null : _pickImage,
                  color: theme.iconTheme.color?.withOpacity(0.7),
                  tooltip: "Attach Image",
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          _isListening ? "Listening..." : "Ask or describe...",
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _buildVoiceOrSendButton(theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return FadeIn(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0, left: 40, right: 40),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_pickedImageBytes!,
                  height: 120, width: double.infinity, fit: BoxFit.cover),
            ),
            IconButton(
              icon: const CircleAvatar(
                radius: 14,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
              onPressed: () => setState(() => {
                _pickedImageBytes = null,
                _pickedImageMimeType = null,
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceOrSendButton(ThemeData theme) {
    bool hasContent =
        _textController.text.isNotEmpty || _pickedImageBytes != null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return ScaleTransition(child: child, scale: animation);
      },
      child: hasContent
          ? _buildSendButton(theme)
          : _buildMicButton(theme),
    );
  }

  Widget _buildMicButton(ThemeData theme) {
    return AvatarGlow(
      key: const ValueKey('mic_button'),
      animate: _isListening,
      glowColor: theme.colorScheme.secondary,
      duration: const Duration(milliseconds: 2000),
      repeat: true,
      child: IconButton.filled(
        icon: Icon(_isListening ? Icons.stop_rounded : Icons.mic_none_rounded),
        onPressed: _isLoading ? null : _toggleListening,
        style: IconButton.styleFrom(
            padding: const EdgeInsets.all(12),
            backgroundColor:
                _isListening ? theme.colorScheme.error : theme.colorScheme.secondary,
            disabledBackgroundColor:
                theme.colorScheme.secondary.withOpacity(0.5)),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    return IconButton.filled(
      key: const ValueKey('send_button'),
      icon: const Icon(Icons.send_rounded),
      onPressed: _isLoading ? null : _sendMessage,
      style: IconButton.styleFrom(
          padding: const EdgeInsets.all(12),
          backgroundColor: theme.colorScheme.primary,
          disabledBackgroundColor: theme.colorScheme.primary.withOpacity(0.5)),
    );
  }
}