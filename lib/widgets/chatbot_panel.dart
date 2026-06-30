import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/gemini_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../models/conversation_message.dart';
import '../utils/gemini_payload_util.dart';
import '../utils/chat_guard.dart';

class ChatbotPanel extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;

  const ChatbotPanel({super.key, required this.isOpen, required this.onClose});

  @override
  State<ChatbotPanel> createState() => _ChatbotPanelState();
}

class _ChatbotPanelState extends State<ChatbotPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  double _panelWidth = 340;
  static const double _minWidth = 280;

  // Track pending confirmations: msgId → parsed payload
  // Rebuilt from StorageService on init so restarts don't lose pending state
  final Map<String, Map<String, dynamic>> _pendingConfirmations = {};

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    // Restore any unresolved pending confirmations from persisted chat history
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePendingConfirmations());
  }

  /// Rebuild _pendingConfirmations from stored messages.
  /// This handles app restarts: if the user had a pending confirm before closing
  /// the app, the Confirm buttons will reappear automatically.
  void _restorePendingConfirmations() {
    final storage = context.read<StorageService>();
    final history = storage.getChatHistory();
    for (final msg in history) {
      if (msg.role != 'model') continue;
      if (GeminiPayloadUtil.confirmationHandled(msg)) continue;
      final payload = GeminiPayloadUtil.parsePayload(msg.text);
      if (payload == null) continue;
      if (!GeminiPayloadUtil.needsConfirmation(payload)) continue;
      // Found an unresolved confirmation — restore it
      setState(() => _pendingConfirmations[msg.id] = payload);
    }
  }

  @override
  void didUpdateWidget(ChatbotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _slideController.forward();
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        _slideController.reverse();
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Send message ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (context.read<GeminiService>().isGenerating) return;

    // Check if user is confirming a pending plan via text
    final lowerText = text.toLowerCase().trim();
    final isConfirmation = _isConfirmPhrase(lowerText);

    if (isConfirmation && _pendingConfirmations.isNotEmpty) {
      final msgId = _pendingConfirmations.keys.last;
      final payload = _pendingConfirmations[msgId]!;
      _inputController.clear();

      // Save user "yes" message
      final storage = context.read<StorageService>();
      final userMsg = ConversationMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_user',
        timestamp: DateTime.now(),
        role: 'user',
        text: text,
      );
      await storage.saveChatMessage(userMsg);

      // Execute actions
      await _confirmAction(msgId, payload);

      // Acknowledge in chat
      final confirmReply = ConversationMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_model',
        timestamp: DateTime.now().add(const Duration(milliseconds: 1)),
        role: 'model',
        text: json.encode({
          'message': 'Done! Everything has been set up for you.',
          'requires_confirmation': false,
          'actions': <dynamic>[],
          'proactive_hint': null,
        }),
        actionsExecuted: const ['auto_executed'],
      );
      await storage.saveChatMessage(confirmReply);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    // Client-side scope guard — instant local refusal
    final refusal = ChatGuard.checkScope(text);
    if (refusal != null) {
      _inputController.clear();
      _showLocalResponse(text, refusal);
      return;
    }

    _inputController.clear();
    final gemini = context.read<GeminiService>();
    final result = await gemini.sendUserQuery(text);

    if (result != null && result['requires_confirmation'] == true) {
      final msgId = result['_message_id'] as String?;
      if (msgId != null) {
        final payload = GeminiPayloadUtil.parsePayload(
          json.encode(Map<String, dynamic>.from(result)..remove('_message_id')),
        );
        setState(() => _pendingConfirmations[msgId] = payload ?? result);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  bool _isConfirmPhrase(String text) {
    const phrases = [
      'yes', 'yeah', 'yep', 'yup', 'sure', 'ok', 'okay', 'ok!', 'yes!',
      'do it', 'go ahead', 'confirm', 'confirmed', 'proceed', "let's do it",
      'sounds good', 'looks good', 'done', 'great', 'perfect', 'apply it',
      'set it up', 'please do', 'go for it', 'apply', 'execute',
    ];
    return phrases.any((p) =>
        text == p || text.startsWith('$p ') || text.endsWith(' $p'));
  }

  void _showLocalResponse(String userText, String botResponse) {
    final storage = context.read<StorageService>();
    final now = DateTime.now();
    storage.saveChatMessage(ConversationMessage(
      id: 'msg_${now.millisecondsSinceEpoch}_user',
      timestamp: now,
      role: 'user',
      text: userText,
    ));
    storage.saveChatMessage(ConversationMessage(
      id: 'msg_${now.millisecondsSinceEpoch}_model',
      timestamp: now.add(const Duration(milliseconds: 1)),
      role: 'model',
      text: json.encode({
        'message': botResponse,
        'requires_confirmation': false,
        'actions': <dynamic>[],
        'proactive_hint': null,
      }),
      actionsExecuted: const ['auto_executed'],
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // ── Confirm / Cancel / Edit ───────────────────────────────────────────────

  Future<void> _confirmAction(String msgId, Map<String, dynamic> payload) async {
    final gemini = context.read<GeminiService>();
    final storage = context.read<StorageService>();

    // Remove from pending immediately to prevent double-execution
    setState(() => _pendingConfirmations.remove(msgId));

    // Execute the actions
    final actions = GeminiPayloadUtil.normalizeActions(
        List<dynamic>.from(payload['actions'] ?? []));
    await gemini.executeParsedActions(actions);

    // Mark the message as confirmed
    await storage.updateChatMessageStatus(msgId, ['confirmation_confirmed']);
  }

  Future<void> _cancelAction(String msgId) async {
    final storage = context.read<StorageService>();
    setState(() => _pendingConfirmations.remove(msgId));
    await storage.updateChatMessageStatus(msgId, ['confirmation_cancelled']);
    await storage.saveChatMessage(ConversationMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_model',
      timestamp: DateTime.now(),
      role: 'model',
      text: json.encode({
        'message': "No problem, cancelled. Let me know if you'd like to adjust anything.",
        'requires_confirmation': false,
        'actions': <dynamic>[],
        'proactive_hint': null,
      }),
      actionsExecuted: const ['auto_executed'],
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _editAction(Map<String, dynamic> payload) {
    final summary = payload['message']?.toString() ?? '';
    _inputController.text = 'Please change this plan: $summary\n\nMy changes: ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen && _slideController.isDismissed) return const SizedBox.shrink();

    final maxWidth = MediaQuery.of(context).size.width;

    return SlideTransition(
      position: _slideAnim,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _panelWidth -= details.delta.dx;
              _panelWidth = _panelWidth.clamp(_minWidth, maxWidth);
            });
          },
          child: SizedBox(
            width: _panelWidth,
            height: double.infinity,
            child: _buildPanelContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary.withValues(alpha: 0.95),
            border: Border(
              left: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.6), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(-4, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildOfflineBanner(),
              Expanded(child: _buildMessageList()),
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Text(
            'planMate AI',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Clear chat button
          Consumer<StorageService>(
            builder: (context, storage, _) {
              final hasHistory = storage.getChatHistory().isNotEmpty;
              return Tooltip(
                message: 'Clear chat history',
                child: GestureDetector(
                  onTap: hasHistory
                      ? () => _confirmClearChat(context, storage)
                      : null,
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: hasHistory
                          ? AppColors.danger.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: hasHistory
                          ? AppColors.danger.withValues(alpha: 0.8)
                          : AppColors.textMuted.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              );
            },
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: const Icon(Icons.close,
                color: AppColors.textSecondary, size: 18),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context, StorageService storage) {
    final msgCount = storage.getChatHistory().length;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_forever_rounded,
                      color: AppColors.danger, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Clear Chat History',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'This will permanently delete $msgCount message${msgCount == 1 ? '' : 's'}. '
              'The AI will start fresh with no memory of previous conversations.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.inter(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.delete_forever_rounded, size: 15),
                    label: Text('Clear',
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      Navigator.pop(context);
                      setState(() => _pendingConfirmations.clear());
                      await storage.clearConversationHistory();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Consumer<SyncService>(
      builder: (context, sync, _) {
        if (sync.isOnline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.warning.withValues(alpha: 0.1),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: AppColors.warning, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI chat requires internet. You can still use the app manually.',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.warning),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageList() {
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        final messages = storage.getChatHistory();

        return Consumer<GeminiService>(
          builder: (context, gemini, _) {
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: messages.length +
                  (gemini.isGenerating ? 1 : 0) +
                  (messages.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (messages.isEmpty && i == 0) {
                  return _buildStarterChips();
                }
                final msgIndex = messages.isEmpty ? i - 1 : i;
                if (msgIndex == messages.length && gemini.isGenerating) {
                  return _buildStreamingBubble(gemini.currentStreamedResponse);
                }
                final msg = messages[msgIndex];
                return _buildMessageBubble(msg);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStarterChips() {
    final starters = [
      ('Plan my day 🗓️', 'Help me plan the rest of my day'),
      ("What's overdue?", 'Which of my tasks are overdue?'),
      ('Add a task ➕', 'I want to add a new task'),
      ('Rescue mode 🏳️', "I'm overwhelmed, help me prioritise"),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accentPrimary.withValues(alpha: 0.08),
                  AppColors.accentSecondary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('planMate AI',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      Text('What can I help with today?',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: starters
                .map((s) => GestureDetector(
                      onTap: () {
                        _inputController.text = s.$2;
                        _sendMessage();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.borderAccent),
                        ),
                        child: Text(s.$1,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.accentPrimary)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ConversationMessage msg) {
    final isUser = msg.role == 'user';

    String displayText = GeminiPayloadUtil.displayText(msg);
    Map<String, dynamic>? parsedPayload;
    if (!isUser) {
      parsedPayload = GeminiPayloadUtil.parsePayload(msg.text);
    }

    final proactiveHint = parsedPayload?['proactive_hint'] as String?;

    final showConfirmButtons = !isUser &&
        parsedPayload != null &&
        GeminiPayloadUtil.needsConfirmation(parsedPayload) &&
        !GeminiPayloadUtil.confirmationHandled(msg) &&
        _pendingConfirmations.containsKey(msg.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _copyText(displayText),
            child: Row(
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 6, bottom: 2),
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 11, color: Colors.white),
                  ),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isUser ? AppColors.accentGradient : null,
                      color: isUser ? null : AppColors.bgElevated,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isUser ? 14 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 14),
                      ),
                      border: isUser
                          ? null
                          : Border.all(
                              color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      displayText,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isUser ? Colors.white : AppColors.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Timestamp
          Padding(
            padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 30),
            child: Text(
              _formatTime(msg.timestamp),
              style: GoogleFonts.inter(
                  fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          // Proactive hint chip
          if (!isUser && proactiveHint != null && proactiveHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 6),
              child: GestureDetector(
                onTap: () {
                  _inputController.text = proactiveHint;
                  _sendMessage();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderAccent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          size: 12, color: AppColors.accentPrimary),
                      const SizedBox(width: 4),
                      Text(proactiveHint,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.accentPrimary)),
                    ],
                  ),
                ),
              ),
            ),
          // Confirmation buttons
          if (showConfirmButtons)
            _buildConfirmationButtons(msg.id, _pendingConfirmations[msg.id]!),
        ],
      ),
    );
  }

  Widget _buildStreamingBubble(String partialText) {
    final display = partialText.isEmpty
        ? ''
        : (() {
            try {
              final parsed = json.decode(partialText) as Map<String, dynamic>;
              return parsed['message'] as String? ?? partialText;
            } catch (_) {
              return partialText;
            }
          })();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 6, bottom: 2),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child:
                const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
          ),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.3)),
              ),
              child: display.isEmpty
                  ? _buildTypingIndicator()
                  : Text(
                      display,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.45,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => _BouncingDot(delay: i * 180)),
    );
  }

  Widget _buildConfirmationButtons(
      String msgId, Map<String, dynamic> payload) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 8),
      child: Row(
        children: [
          _ActionButton(
            label: 'Confirm',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            onTap: () async {
              await _confirmAction(msgId, payload);
              // Success feedback message
              final botMsg = ConversationMessage(
                id: 'msg_${DateTime.now().millisecondsSinceEpoch}_model',
                timestamp: DateTime.now(),
                role: 'model',
                text: json.encode({
                  'message': 'Done! Everything has been set up.',
                  'requires_confirmation': false,
                  'actions': <dynamic>[],
                  'proactive_hint': null,
                }),
                actionsExecuted: const ['auto_executed'],
              );
              await context.read<StorageService>().saveChatMessage(botMsg);
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
            },
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            color: AppColors.accentPrimary,
            onTap: () => _editAction(payload),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Cancel',
            icon: Icons.cancel_outlined,
            color: AppColors.danger,
            onTap: () => _cancelAction(msgId),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Consumer<SyncService>(
        builder: (context, sync, _) {
          final isOffline = !sync.isOnline;
          final gemini = context.watch<GeminiService>();

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 100),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: TextField(
                      controller: _inputController,
                      enabled: !isOffline && !gemini.isGenerating,
                      maxLines: null,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: isOffline
                            ? 'Offline — chat unavailable'
                            : 'Message planMate AI...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!isOffline && !gemini.isGenerating) _sendMessage();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: (isOffline || gemini.isGenerating) ? null : _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: (isOffline || gemini.isGenerating)
                          ? null
                          : AppColors.accentGradient,
                      color: (isOffline || gemini.isGenerating)
                          ? AppColors.border
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: gemini.isGenerating
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _BouncingDot extends StatefulWidget {
  final int delay;
  const _BouncingDot({required this.delay});
  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: AppColors.textSecondary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
