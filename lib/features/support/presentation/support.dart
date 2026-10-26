import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Loads the rides Support can be asked about.
typedef SupportRidesLoader = Future<List<SupportRide>> Function();

class SupportHome extends StatelessWidget {
  const SupportHome({super.key, this.loadRides, this.contact});

  /// Defaults to the rider's ride history (FLOW-8).
  final SupportRidesLoader? loadRides;

  /// Defaults to the support address this build was given, if any.
  final SupportContact? contact;

  static const Color ink = Color(0xFF1D252C);
  static const Color muted = Color(0xFF5C656C);
  static const Color line = Color(0xFFE7EBEE);
  static const Color accent = Color(0xFF2D5878);
  static const Color cta = Color(0xFF11181D);
  static const Color soft = Color(0xFFF4F6F8);
  static const Color accentSoft = Color(0xFFEAF2F8);

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static Future<List<SupportRide>> rides() =>
      AppScope.instance.support.loadRides();

  @override
  Widget build(BuildContext context) {
    final support = contact ?? const SupportContact();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: ink),
                  tooltip: context.l10n.close,
                ),
                const Spacer(),
                Flexible(
                  child: _PillButton(
                    icon: Icons.mail_outline_rounded,
                    label: context.l10n.supportMessages,
                    onTap: () => guardedPush(
                      context,
                      RightToLeftTransition(const SupportMessages()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.supportHelp,
                        style: text(
                          34,
                          weight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.supportWhatHelp,
                        style: text(16, color: muted),
                      ),
                    ],
                  ),
                ),
                const _TeamAvatars(),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.supportSelectARide,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text(16, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                MoveraHitArea(
                  label: context.l10n.supportViewAllRides,
                  onTap: () => guardedPush(
                    context,
                    RightToLeftTransition(
                      SelectSupportRide(loadRides: loadRides),
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      context.l10n.supportViewAll,
                      style: text(14, weight: FontWeight.w500, color: muted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SupportRides(
              load: loadRides ?? rides,
              builder: (context, all) {
                final recent = all.take(3).toList();
                if (recent.isEmpty) {
                  return _EmptyCard(
                    icon: Icons.inbox_outlined,
                    title: context.l10n.supportNoRidesToReview,
                    subtitle: context.l10n.supportRidesAppearHere,
                  );
                }
                return Column(
                  children: [
                    for (final ride in recent)
                      _RideCard(
                        ride: ride,
                        onTap: () => guardedPush(
                          context,
                          RightToLeftTransition(SelectIssue(ride: ride)),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.supportBrowseTopics,
              style: text(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TopicChip(
                  label: context.l10n.rides,
                  onTap: () => guardedPush(
                    context,
                    RightToLeftTransition(
                      SelectSupportRide(loadRides: loadRides),
                    ),
                  ),
                ),
                _TopicChip(
                  label: context.l10n.payments,
                  onTap: () => guardedPush(
                    context,
                    RightToLeftTransition(
                      HelpArticle(
                        title: context.l10n.supportPaymentsTitle,
                        body: context.l10n.supportPaymentsBody,
                      ),
                    ),
                  ),
                ),
                _TopicChip(
                  label: context.l10n.navAccount,
                  onTap: () => guardedPush(
                    context,
                    RightToLeftTransition(
                      HelpArticle(
                        title: context.l10n.supportAccountTitle,
                        body: context.l10n.supportAccountBody,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              context.l10n.supportSomethingElse,
              style: text(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              title: context.l10n.supportMessaging,
              icon: Icons.headset_mic_rounded,
              onTap: () => guardedPush(
                context,
                RightToLeftTransition(const HowCanWeHelp()),
              ),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              title: context.l10n.supportBrowseArticles,
              icon: Icons.menu_book_rounded,
              onTap: () => guardedPush(
                context,
                RightToLeftTransition(const HelpArticles()),
              ),
            ),
            if (support.available) ...[
              const SizedBox(height: 10),
              _ActionCard(
                title: context.l10n.supportEmail,
                icon: Icons.mail_outline_rounded,
                onTap: () async {
                  final opened = await support.openEmail(
                    subject: context.l10n.supportEmailSubject,
                  );
                  if (!opened && context.mounted) {
                    MoveraToast.show(
                      context,
                      context.l10n.supportNoMailApp(support.email),
                    );
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
            _ActionCard(
              title: context.l10n.supportCases,
              icon: Icons.forum_outlined,
              onTap: () => guardedPush(
                context,
                RightToLeftTransition(const SupportMessages()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HowCanWeHelp extends StatelessWidget {
  const HowCanWeHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: context.l10n.supportHowHelp,
      trailing: _exit(context),
      child: ListView(
        children: [
          _LineItem(
            icon: Icons.directions_car_filled_outlined,
            title: context.l10n.supportHelpWithRide,
            onTap: () => guardedPush(
              context,
              RightToLeftTransition(const SelectSupportRide()),
            ),
          ),
          _LineItem(
            icon: Icons.chat_bubble_outline_rounded,
            title: context.l10n.supportSomethingElse,
            onTap: () => guardedPush(
              context,
              RightToLeftTransition(const SupportChat()),
            ),
          ),
        ],
      ),
    );
  }
}

class SelectSupportRide extends StatelessWidget {
  const SelectSupportRide({super.key, this.loadRides});

  /// Defaults to the rider's ride history (FLOW-8).
  final SupportRidesLoader? loadRides;

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: context.l10n.supportSelectRide,
      trailing: _exit(context),
      child: _SupportRides(
        load: loadRides ?? SupportHome.rides,
        builder: (context, rides) => _list(context, rides),
      ),
    );
  }

  Widget _list(BuildContext context, List<SupportRide> rides) {
    final grouped = <String, List<SupportRide>>{};
    for (final ride in rides) {
      grouped.putIfAbsent(ride.monthTitle, () => []).add(ride);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (grouped.isEmpty)
          _EmptyCard(
            icon: Icons.event_busy_outlined,
            title: context.l10n.supportNoRidesYet,
            subtitle: context.l10n.supportRidesAppearHere,
          )
        else
          for (final entry in grouped.entries) ...[
            Text(
              entry.key,
              style: SupportHome.text(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final ride in entry.value)
              _RideRow(
                ride: ride,
                onTap: () => guardedPush(
                  context,
                  RightToLeftTransition(SelectIssue(ride: ride)),
                ),
              ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class SelectIssue extends StatelessWidget {
  const SelectIssue({super.key, required this.ride});

  final SupportRide ride;

  /// The issues in the app language, in the order of [_codes].
  static List<String> get issues => [
    L10n.current.issueChargedMore,
    L10n.current.issueChargedTwice,
    L10n.current.issueLostItem,
    L10n.current.issueRideWithoutMe,
    L10n.current.issueDriverExpectations,
    L10n.current.issueWaitFee,
    L10n.current.issueTips,
  ];

  static const _codes = [
    'charged_more_than_expected',
    'charged_twice',
    'lost_item',
    'ride_without_me',
    'driver_expectations',
    'wait_time_fee',
    'tips_question',
  ];

  /// The reason sent with the message for [issue] ("Something else" and
  /// free text: `other`).
  static String codeFor(String? issue) {
    final index = issue == null ? -1 : issues.indexOf(issue);
    return index < 0 ? 'other' : _codes[index];
  }

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: '',
      trailing: _exit(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _CompactTrip(ride: ride),
          const SizedBox(height: 28),
          Text(
            context.l10n.supportSelectIssue,
            style: SupportHome.text(22, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final issue in issues)
            _LineItem(
              title: issue,
              onTap: () => guardedPush(
                context,
                RightToLeftTransition(SupportChat(ride: ride, issue: issue)),
              ),
            ),
          _LineItem(
            title: context.l10n.supportSomethingElse,
            accent: true,
            onTap: () => guardedPush(
              context,
              RightToLeftTransition(SupportChat(ride: ride)),
            ),
          ),
        ],
      ),
    );
  }
}

class HelpArticles extends StatelessWidget {
  const HelpArticles({super.key});

  /// (title, body) of each article, in the app language.
  static List<(String, String)> get topics {
    final l = L10n.current;
    return [
      (l.helpAboutTitle, l.helpAboutBody),
      (l.helpAppTitle, l.helpAppBody),
      (l.supportAccountTitle, l.supportAccountBody),
      (l.supportPaymentsTitle, l.supportPaymentsBody),
      (l.helpUsingTitle, l.helpUsingBody),
      (l.safetyTitle, l.helpSafetyBody),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: context.l10n.helpArticles,
      trailing: _exit(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: [
          for (final topic in topics)
            _LineItem(
              title: topic.$1,
              onTap: () => guardedPush(
                context,
                RightToLeftTransition(
                  HelpArticle(title: topic.$1, body: topic.$2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HelpArticle extends StatelessWidget {
  const HelpArticle({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: SupportHome.text(15, height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => guardedPush(
                  context,
                  RightToLeftTransition(const HowCanWeHelp()),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: SupportHome.cta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: Text(
                  context.l10n.supportOptions,
                  style: SupportHome.text(
                    15.5,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SupportMessages extends StatelessWidget {
  const SupportMessages({super.key});

  @override
  Widget build(BuildContext context) {
    return _SupportScaffold(
      title: context.l10n.supportMessagesTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // rider-u229: no case list backs this screen, so it never says
          // "No active cases" to a rider who has just sent one.
          _EmptyCard(
            icon: Icons.forum_outlined,
            title: context.l10n.supportCasesNotListed,
            subtitle: context.l10n.supportActiveBody,
          ),
        ],
      ),
    );
  }
}

/// Sends a rider's message about a ride to Movera (`POST
/// /rides/{id}/disputes`, the same review queue as "Report an issue" on the
/// receipt).
typedef SupportMessageSender =
    Future<void> Function({
      required String rideId,
      required String reason,
      String? detail,
    });

/// UI-03: the in-app way to reach Movera about a ride. It used to be a
/// chat whose input read "Support messaging unavailable" — a dead end for a
/// rider with a money problem when the build has no support email. Now a
/// ride issue is a short message form sent to Movera's review queue; with no
/// ride picked it points to the ride list (and to email when configured).
class SupportChat extends StatefulWidget {
  const SupportChat({
    super.key,
    this.ride,
    this.issue,
    this.contact,
    this.send,
  });

  final SupportRide? ride;
  final String? issue;

  /// Defaults to the support address this build was given, if any.
  final SupportContact? contact;

  /// Defaults to the ride dispute endpoint.
  final SupportMessageSender? send;

  /// The trip id a Support row stands for (History keys on-demand rides as
  /// `ondemand-<tripId>`). Null when the row has no id.
  static String? tripIdOf(SupportRide? ride) {
    final id = ride?.id?.trim();
    if (id == null || id.isEmpty) return null;
    const prefix = 'ondemand-';
    final trip = id.startsWith(prefix) ? id.substring(prefix.length) : id;
    return trip.isEmpty ? null : trip;
  }

  @override
  State<SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<SupportChat> {
  final TextEditingController _detail = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _sentText;
  String? _error;

  String? get _tripId => SupportChat.tripIdOf(widget.ride);

  @override
  void initState() {
    super.initState();
    _detail.addListener(_onDetailChanged);
  }

  @override
  void dispose() {
    _detail
      ..removeListener(_onDetailChanged)
      ..dispose();
    super.dispose();
  }

  void _onDetailChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit =>
      !_sending &&
      !_sent &&
      (widget.issue != null || _detail.text.trim().isNotEmpty);

  Future<void> _submit() async {
    final tripId = _tripId;
    if (tripId == null || !_canSubmit) return;
    final detail = _detail.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final send =
          widget.send ??
          ({required String rideId, required String reason, String? detail}) =>
              AppScope.instance.rideComplete.submitDispute(
                rideId: rideId,
                reason: reason,
                detail: detail,
              );
      await send(
        rideId: tripId,
        reason: SelectIssue.codeFor(widget.issue),
        detail: [
          if (widget.issue != null) widget.issue!,
          if (detail.isNotEmpty) detail,
        ].join('\n'),
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
        _sentText = detail.isEmpty ? null : detail;
      });
      _detail.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = context.l10n.supportSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final issue = widget.issue;
    final canSend = _tripId != null;
    final contact = widget.contact ?? const SupportContact();
    final script = AppScope.instance.support.chat(ride: canSend ? ride : null);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: SupportHome.ink,
                    ),
                    tooltip: context.l10n.close,
                  ),
                  Text(
                    context.l10n.supportHelp,
                    style: SupportHome.text(18, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _PillButton(
                    label: context.l10n.close,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SupportHome.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                children: [
                  if (ride != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SupportHome.accentSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD5E3EC)),
                      ),
                      child: _RideCard(ride: ride, compact: true),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _MiraMark(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              script.welcome,
                              style: SupportHome.text(15, height: 1.45),
                            ),
                            if (issue != null) ...[
                              const SizedBox(height: 14),
                              _Bubble(text: issue),
                            ],
                            if (canSend && !_sent) ...[
                              const SizedBox(height: 12),
                              Text(
                                script.issueAck,
                                style: SupportHome.text(15, height: 1.45),
                              ),
                            ],
                            if (_sent) ...[
                              if (_sentText != null) ...[
                                const SizedBox(height: 12),
                                _Bubble(text: _sentText!),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                script.followUp,
                                key: const ValueKey('support-message-sent'),
                                style: SupportHome.text(15, height: 1.45),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  _error!,
                  key: const ValueKey('support-message-error'),
                  style: SupportHome.text(13, color: const Color(0xFFB42318)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: canSend
                  ? (_sent ? _doneButton(context) : _composer())
                  : _noRideActions(context, contact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return TextField(
      key: const ValueKey('support-message-field'),
      controller: _detail,
      enabled: !_sending,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: widget.issue == null
            ? context.l10n.supportTellWhatHappened
            : context.l10n.supportAddDetails,
        hintStyle: SupportHome.text(14, color: SupportHome.muted),
        filled: true,
        fillColor: SupportHome.soft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        suffixIcon: _sending
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: const ValueKey('support-message-send'),
                tooltip: context.l10n.supportSendToMovera,
                onPressed: _canSubmit ? _submit : null,
                icon: Icon(
                  Icons.send_rounded,
                  color: _canSubmit ? SupportHome.ink : SupportHome.muted,
                ),
              ),
      ),
    );
  }

  Widget _doneButton(BuildContext context) => _wideButton(
    label: context.l10n.done,
    onPressed: () => Navigator.pop(context),
  );

  Widget _noRideActions(BuildContext context, SupportContact contact) {
    if (contact.available) {
      return _wideButton(
        label: context.l10n.supportEmail,
        onPressed: () async {
          final opened = await contact.openEmail(
            subject: context.l10n.supportEmailSubject,
          );
          if (!opened && context.mounted) {
            MoveraToast.show(
              context,
              context.l10n.supportNoMailApp(contact.email),
            );
          }
        },
      );
    }
    return _wideButton(
      label: context.l10n.supportChooseRide,
      onPressed: () => guardedPush(
        context,
        RightToLeftTransition(const SelectSupportRide()),
      ),
    );
  }

  Widget _wideButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: SupportHome.cta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Text(
          label,
          style: SupportHome.text(
            15.5,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: SupportHome.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: SupportHome.text(14, height: 1.4, color: Colors.white),
        ),
      ),
    );
  }
}

class _SupportScaffold extends StatelessWidget {
  const _SupportScaffold({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: SupportHome.ink,
                    ),
                    tooltip: context.l10n.back,
                  ),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  title,
                  style: SupportHome.text(
                    28,
                    weight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

Widget _exit(BuildContext context) {
  return TextButton(
    onPressed: () => Navigator.popUntil(context, AppRoutes.isHomeRoute),
    child: Text(
      context.l10n.supportExit,
      style: SupportHome.text(
        14,
        weight: FontWeight.w600,
        color: SupportHome.accent,
      ),
    ),
  );
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, this.onTap, this.compact = false});

  final SupportRide ride;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: SupportHome.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              ride.image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_car_filled_rounded,
                color: SupportHome.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SupportHome.text(14.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  ride.whenLabel,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
                Text(
                  ride.priceLabel,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.onTap});

  final SupportRide ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: SupportHome.soft,
              child: Icon(
                ride.failed || ride.cancelled
                    ? Icons.no_crash_outlined
                    : Icons.directions_car_filled_outlined,
                color: SupportHome.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SupportHome.text(14.5, weight: FontWeight.w600),
                  ),
                  Text(
                    ride.whenLabel,
                    style: SupportHome.text(12.5, color: SupportHome.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // rider-u230: a cancelled ride reads as on the other Support
              // screens (its fee, not the full fare).
              ride.cancelled
                  ? ride.priceLabel
                  : ride.failed
                  ? context.l10n.supportFailed
                  // rider-r5-48: an ended-early charge to the öre.
                  : formatMajor(
                      ride.price,
                      ride.currency,
                      whole: !ride.endedEarly,
                    ),
              style: SupportHome.text(14, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTrip extends StatelessWidget {
  const _CompactTrip({required this.ride});

  final SupportRide ride;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_car_filled_outlined,
            color: SupportHome.ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.title,
                  style: SupportHome.text(14, weight: FontWeight.w600),
                ),
                Text(
                  ride.longWhen,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SupportHome.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SupportHome.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SupportHome.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: SupportHome.text(
                    13,
                    color: SupportHome.muted,
                    height: 1.4,
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupportHome.soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: SupportHome.text(15, weight: FontWeight.w600),
                ),
              ),
              Icon(icon, color: SupportHome.accent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.title,
    required this.onTap,
    this.icon,
    this.accent = false,
  });

  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: icon == null ? null : Icon(icon, color: SupportHome.ink),
          title: Text(
            title,
            style: SupportHome.text(
              15.5,
              weight: FontWeight.w500,
              color: accent ? SupportHome.accent : SupportHome.ink,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: accent ? SupportHome.accent : SupportHome.muted,
          ),
        ),
        const Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: SupportHome.line,
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: SupportHome.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: SupportHome.text(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SupportHome.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupportHome.soft,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: SupportHome.ink),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SupportHome.text(13.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamAvatars extends StatelessWidget {
  const _TeamAvatars();

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF2D5878), Color(0xFF4A7A96), Color(0xFF1D252C)];
    return SizedBox(
      width: 86,
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              left: i * 22.0,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colors[i],
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiraMark extends StatelessWidget {
  const _MiraMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF2D5878),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
    );
  }
}

/// Loads the rider's rides once and builds with them; a short spinner
/// while loading, the empty state when the history cannot be read.
class _SupportRides extends StatefulWidget {
  const _SupportRides({required this.load, required this.builder});

  final SupportRidesLoader load;
  final Widget Function(BuildContext context, List<SupportRide> rides) builder;

  @override
  State<_SupportRides> createState() => _SupportRidesState();
}

class _SupportRidesState extends State<_SupportRides> {
  late Future<List<SupportRide>> _rides = _load();

  Future<List<SupportRide>> _load() =>
      widget.load().timeout(const Duration(seconds: 8));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SupportRide>>(
      future: _rides,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // rider-r3-2: a history that could not be read is not "no rides".
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmptyCard(
                icon: Icons.cloud_off_outlined,
                title: context.l10n.historyLoadFailed,
                subtitle: context.l10n.historyLoadFailedBody,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _rides = _load();
                  }),
                  child: Text(context.l10n.retry),
                ),
              ),
            ],
          );
        }
        return widget.builder(context, snapshot.data ?? const []);
      },
    );
  }
}
