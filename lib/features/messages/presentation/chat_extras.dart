import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';

/// v0.18.56 §78 (owner Q81): one line under the chat's title bar instead of
/// a Report / Block button.
class ChatHeaderLine extends StatelessWidget {
  const ChatHeaderLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('chat-header-line'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: screenHorizPadding,
        vertical: 8,
      ),
      color: const Color(0xFFF4F6F7),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF5C656C),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// v0.18.56 §78: the country's quick replies for the rider, in the app
/// language; a tap sends the chip.
class ChatQuickReplies extends StatelessWidget {
  const ChatQuickReplies({
    super.key,
    required this.replies,
    required this.onTap,
  });

  final List<ChatQuickReply> replies;
  final ValueChanged<ChatQuickReply> onTap;

  @override
  Widget build(BuildContext context) {
    final language = context.l10n.localeName;
    return Semantics(
      container: true,
      label: context.l10n.chatQuickReplies,
      child: SizedBox(
        key: const ValueKey<String>('chat-quick-replies'),
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: replies.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final reply = replies[index];
            return ActionChip(
              key: ValueKey<String>('chat-quick-reply-${reply.id}'),
              label: Text(reply.textIn(language)),
              onPressed: () => onTap(reply),
              backgroundColor: const Color(0xffF6F6F6),
              side: BorderSide.none,
              shape: const StadiumBorder(),
              labelStyle: TextStyle(color: AppColor.title, fontSize: 13),
            );
          },
        ),
      ),
    );
  }
}

/// The blue "Translate to `language`" / "See original" link under a message.
class ChatTranslateLink extends StatelessWidget {
  const ChatTranslateLink({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF1565C0),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
