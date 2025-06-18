// At the top of lib/screens/widgets/ai_chat_panel.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:animate_do/animate_do.dart';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../models/chat_messageai.dart';
import '../../services/gemini_service.dart';

class AiChatPanel extends StatefulWidget {
  final String? initialPrompt;
  final VoidCallback onClose;

  const AiChatPanel({
    super.key,
    this.initialPrompt,
    required this.onClose,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GeminiService _geminiService = GeminiService();
  final List<ChatMessage> _messages = [];

  bool _isLoading = false;
  String? _lastHandledInitialPrompt;

  static const List<String> _suggestedPrompts = [
    "How to fix a leaky faucet?",
    "Best paint for exterior walls?",
    "Ideas for a small garden?",
    "What causes a circuit breaker to trip?"
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt == null || widget.initialPrompt!.isEmpty) {
      _messages.add(ChatMessage(
          text: "Hello! I'm your FixIt AI Assistant. How can I help you today?",
          messageType: MessageType.bot));
    }
  }

  @override
  void didUpdateWidget(covariant AiChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPrompt != null &&
        widget.initialPrompt != _lastHandledInitialPrompt) {
      _lastHandledInitialPrompt = widget.initialPrompt;
      _sendMessage(prefilledText: widget.initialPrompt!);
    }
  }

  // --- Core Logic: Text Streaming from Gemini ---
  void _sendMessage({String? prefilledText}) async {
    final text = prefilledText ?? _textController.text.trim();
    if (text.isEmpty) return;

    // Add user message to UI
    setState(() {
      _messages.add(ChatMessage(text: text, messageType: MessageType.user));
      _isLoading = true; // Start the "typing" indicator
    });
    if (prefilledText == null) _textController.clear();
    _scrollToBottom();

    try {
      // Add the empty bot message here, INSIDE the try block
      final botMessage = ChatMessage(text: "", messageType: MessageType.bot);
      setState(() {
        _messages.add(botMessage);
      });

      final stream =
          _geminiService.model.generateContentStream([Content.text(text)]);

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
        // Remove the empty bot message that we added in the 'try' block if it exists
        if (_messages.isNotEmpty &&
            _messages.last.messageType == MessageType.bot) {
          _messages.removeLast();
        }
        // Add a NEW message with the correct error type
        _messages.add(ChatMessage(
          text: "An error occurred. Please check your connection or API key.",
          messageType: MessageType.error,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
          text: "Chat cleared! How can I assist you now?",
          messageType: MessageType.bot));
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        bottomLeft: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: 380,
          height: 550, // Increased height for better view
          decoration: BoxDecoration(
            color: isDark
                ? theme.scaffoldBackgroundColor.withOpacity(0.85)
                : theme.cardColor.withOpacity(0.9),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
            border:
                Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 25,
                offset: const Offset(-5, 5),
              ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
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

  // --- Beautiful UI Widgets ---

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Text("AI Assistant",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearChat();
            },
            icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_sweep_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Clear Chat'),
                ]),
              ),
            ],
          ),
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

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    return FadeInUp(
      from: 20,
      duration: const Duration(milliseconds: 400),
      child: Align(
        alignment: message.messageType == MessageType.user
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: _buildBubbleContent(message, theme),
      ),
    );
  }

  Widget _buildBubbleContent(ChatMessage message, ThemeData theme) {
    bool isUser = message.messageType == MessageType.user;
    bool isError = message.messageType == MessageType.error;

    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      margin: const EdgeInsets.symmetric(vertical: 5),
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The main message content, now with Markdown support
          MarkdownBody(
            data: message.text,
            selectable: true,
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
              // You can customize more styles here (headings, blockquotes, etc.)
            ),
          ),
          // Copy button for bot/error messages
          if (!isUser) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.bottomRight,
              child: IconButton(
                icon: Icon(Icons.copy_all_outlined,
                    size: 16, color: theme.iconTheme.color?.withOpacity(0.6)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Copied to clipboard!'),
                    duration: Duration(seconds: 1),
                  ));
                },
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ]
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
                          color: const Color.fromARGB(102, 26, 34, 3)),
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
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(
              3,
              (index) => FadeIn(
                delay: Duration(milliseconds: 200 * index),
                child: Bounce(
                  infinite: true,
                  delay: Duration(milliseconds: 200 * index),
                  child: CircleAvatar(
                      radius: 4,
                      backgroundColor: theme.iconTheme.color?.withOpacity(0.4)),
                ),
              ),
            ).expand((widget) => [widget, const SizedBox(width: 6)]).toList()
              ..removeLast(),
          ],
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
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: "Ask about a fix...",
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              onPressed: _isLoading ? null : () => _sendMessage(),
              style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  backgroundColor: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
