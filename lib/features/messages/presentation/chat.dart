import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/presentation/chat_appbar.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/custom_textfield.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

class Chat extends StatefulWidget {
  const Chat({super.key, this.driverName, this.rideId, this.controller});

  final String? driverName;
  final String? rideId;

  /// Optional injection seam for widget tests. Without it the screen opens
  /// the ride's shared conversation, on the live wire's transport where
  /// there is one (contract v0.5.4) and read-only in the demo.
  final MessagesController? controller;

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final MessagesController _chat;
  late final bool _ownsController = widget.controller == null;
  int _shownCount = 0;

  @override
  void initState() {
    super.initState();
    final rideId = widget.rideId?.trim() ?? '';
    _chat =
        widget.controller ??
        MessagesController.forRide(
          rideId,
          transport: rideId.isEmpty ? null : AppScope.instance.tripMessages,
        );
    _chat.markAllRead();
    _shownCount = _chat.messages.length;
    _chat.addListener(_onConversationChanged);
    _chat.onSendFailed = _onSendFailed;
    // The live transport never reads the event stream, so new messages are
    // asked for while this screen is open (contract v0.5.4).
    _chat.startPolling(MessagesController.chatPollInterval);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToEnd(jump: true),
    );
  }

  @override
  void dispose() {
    _chat.stopPolling();
    _chat.removeListener(_onConversationChanged);
    _chat.onSendFailed = null;
    if (_ownsController) _chat.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onConversationChanged() {
    if (!mounted) return;
    // The rider is looking at the conversation: what arrives is read.
    if (_chat.unreadCount > 0) {
      _chat.markAllRead();
      return;
    }
    final grew = _chat.messages.length > _shownCount;
    _shownCount = _chat.messages.length;
    setState(() {});
    if (grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _onSendFailed(ChatMessage message, Object error) {
    if (!mounted) return;
    MoveraToast.show(context, context.l10n.chatSendFailed);
  }

  void _send() {
    if (!_chat.send(_messageController.text)) return;
    _messageController.clear();
  }

  void _scrollToEnd({bool jump = false}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (jump) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _chat.canSendMessages;
    return Scaffold(
      backgroundColor: const Color(0xffFAFAFA),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(ResSize.h * 75),
        child: ChatAppBar(driverName: widget.driverName),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          12.height,
          Expanded(
            child: _chat.messages.isEmpty
                ? Center(
                    child: MoveraEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: context.l10n.chatNoMessages,
                      message: context.l10n.chatEmptyBody,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _chat.messages.length,
                    itemBuilder: (context, index) {
                      final message = _chat.messages[index];
                      if (message.isSystem) {
                        return SystemMessageBubble(message: message);
                      }
                      return message.fromRider
                          ? RiderMessageBubble(
                              message: message,
                              onRetry: () => _chat.retry(message),
                            )
                          : DriverMessageBubble(message: message);
                    },
                  ),
          ),
          Container(
            width: double.infinity,
            color: AppColor.white,
            padding: EdgeInsets.fromLTRB(
              screenHorizPadding,
              10,
              screenHorizPadding,
              12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!canSend) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      MessagesController.sendUnavailableMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5C656C),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  8.height,
                ],
                SizedBox(
                  height: ResSize.h * 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: customTextfield(
                          borderColor: Colors.transparent,
                          borderWidth: 0,
                          textColor: AppColor.black,
                          controller: _messageController,
                          fontSize: 14,
                          hint: context.l10n.chatSendHint,
                          fillColor: const Color(0xffF6F6F6),
                          borderRadius: 32,
                          hintTextColor: const Color(0xff969696),
                          contentHorizPadding: 14,
                          contentVertPadding: 14,
                          textInputAction: canSend
                              ? TextInputAction.send
                              : null,
                          onFieldSubmitted: canSend ? (_) => _send() : null,
                        ),
                      ),
                      10.width,
                      Semantics(
                        button: true,
                        enabled: canSend,
                        label: canSend
                            ? context.l10n.chatSendSemantics
                            : context.l10n.chatSendUnavailableSemantics,
                        child: ExcludeSemantics(
                          child: Material(
                            color: canSend
                                ? AppColor.primary
                                : const Color(0xffF6F6F6),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: canSend ? _send : null,
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                height: ResSize.h * 48,
                                width: ResSize.w * 48,
                                child: Padding(
                                  padding: EdgeInsets.all(ResSize.w * 12),
                                  child: Image.asset(
                                    AppAssets.send,
                                    color: canSend ? AppColor.whiteText : null,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// rider-48: the app's 24-hour clock ('15:05'), as on the ride sheet,
/// not Material's 12-hour English default.
String? _messageTime(BuildContext context, DateTime? sentAt) {
  if (sentAt == null) return null;
  return L10n.formatTime(sentAt.toLocal());
}

class RiderMessageBubble extends StatelessWidget {
  const RiderMessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;

  /// Sends a message the server never took again (same message, same
  /// idempotency key). The bubble says so and takes the tap.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final time = _messageTime(context, message.sentAt);
    final failed = message.delivery == ChatDelivery.failed;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResSize.w * 80,
        ResSize.h * 10,
        screenHorizPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Semantics(
            button: failed && onRetry != null,
            child: InkWell(
              onTap: failed ? onRetry : null,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  ResSize.w * 12,
                  ResSize.h * 9,
                  ResSize.w * 12,
                  ResSize.h * 11,
                ),
                decoration: BoxDecoration(
                  color: failed
                      ? AppColor.primary.withValues(alpha: 0.55)
                      : AppColor.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextWidget(
                  text: message.text,
                  color: AppColor.whiteText,
                  fontSize: 14,
                  fontWeight: fwNormal,
                ),
              ),
            ),
          ),
          if (failed) ...[
            5.height,
            TextWidget(
              text: context.l10n.chatNotSentRetry,
              color: const Color(0xffC62828),
              fontSize: 12,
              fontWeight: fwMedium,
            ),
          ] else if (time != null) ...[
            5.height,
            TextWidget(
              text: time,
              color: const Color(0xff858F94),
              fontSize: 12,
              fontWeight: fwNormal,
            ),
          ],
        ],
      ),
    );
  }
}

class DriverMessageBubble extends StatelessWidget {
  const DriverMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = _messageTime(context, message.sentAt);
    // Contract `from: support` is Movera's support team, not the driver.
    final fromSupport = message.sender == ChatMessageSender.support;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenHorizPadding,
        ResSize.h * 10,
        ResSize.w * 80,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fromSupport) ...[
            TextWidget(
              text: context.l10n.chatSupportSender,
              color: const Color(0xff5C656C),
              fontSize: 12,
              fontWeight: fwMedium,
            ),
            4.height,
          ],
          Container(
            padding: EdgeInsets.fromLTRB(
              ResSize.w * 12,
              ResSize.h * 9,
              ResSize.w * 12,
              ResSize.h * 11,
            ),
            decoration: BoxDecoration(
              color: const Color(0xffF1F3F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextWidget(
              text: message.text,
              fontSize: 14,
              color: AppColor.title,
              fontWeight: fwNormal,
            ),
          ),
          if (time != null) ...[
            5.height,
            TextWidget(
              text: time,
              color: const Color(0xff858F94),
              fontSize: 12,
              fontWeight: fwNormal,
            ),
          ],
        ],
      ),
    );
  }
}

class SystemMessageBubble extends StatelessWidget {
  const SystemMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = _messageTime(context, message.sentAt);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenHorizPadding,
        ResSize.h * 12,
        screenHorizPadding,
        0,
      ),
      child: Semantics(
        label: context.l10n.chatSystemMessage(message.text),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResSize.w * 14,
                vertical: ResSize.h * 9,
              ),
              decoration: BoxDecoration(
                color: const Color(0xffECEFF1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextWidget(
                text: message.text,
                fontSize: 12.5,
                color: AppColor.title,
                fontWeight: fwMedium,
              ),
            ),
            if (time != null) ...[
              4.height,
              TextWidget(
                text: time,
                color: const Color(0xff858F94),
                fontSize: 11,
                fontWeight: fwNormal,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
