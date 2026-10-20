import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/presentation/chat_appbar.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/custom_textfield.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

class Chat extends StatefulWidget {
  const Chat({
    super.key,
    this.driverName,
    this.rideId,
    this.controller,
  });

  final String? driverName;
  final String? rideId;

  /// Optional injection seam for widget tests and, later, the transport adapter.
  final MessagesController? controller;

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final MessagesController _chat;

  @override
  void initState() {
    super.initState();
    _chat = widget.controller ?? MessagesController.forRide(widget.rideId);
    _chat.markAllRead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(jump: true));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
                          ? RiderMessageBubble(message: message)
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
                        ),
                      ),
                      10.width,
                      Semantics(
                        button: true,
                        enabled: false,
                        label: context.l10n.chatSendUnavailableSemantics,
                        child: ExcludeSemantics(
                          child: Material(
                            color: const Color(0xffF6F6F6),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: null,
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                height: ResSize.h * 48,
                                width: ResSize.w * 48,
                                child: Padding(
                                  padding: EdgeInsets.all(ResSize.w * 12),
                                  child: Image.asset(
                                    AppAssets.send,
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

String? _messageTime(BuildContext context, DateTime? sentAt) {
  if (sentAt == null) return null;
  return TimeOfDay.fromDateTime(sentAt.toLocal()).format(context);
}

class RiderMessageBubble extends StatelessWidget {
  const RiderMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = _messageTime(context, message.sentAt);
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
          Container(
            padding: EdgeInsets.fromLTRB(
              ResSize.w * 12,
              ResSize.h * 9,
              ResSize.w * 12,
              ResSize.h * 11,
            ),
            decoration: BoxDecoration(
              color: AppColor.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextWidget(
              text: message.text,
              color: AppColor.whiteText,
              fontSize: 14,
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

class DriverMessageBubble extends StatelessWidget {
  const DriverMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = _messageTime(context, message.sentAt);
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
