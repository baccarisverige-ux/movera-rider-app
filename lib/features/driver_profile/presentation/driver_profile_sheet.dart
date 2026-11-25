import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';

/// v0.18.155 (contract.json#driverProfile; design Rules
/// plan/inspiration-ride-change-2026-11-20/driver-profile-v3.html, our own
/// look in Movera colours): hero header, gold-ringed photo, languages and
/// city pills, three KPIs, compliment tiles (the phone's own emoji),
/// milestones and the latest approved review (first name + month only).
const dpNavy = Color(0xFF0E1B2C);
const dpBlue = Color(0xFF1F6FEB);
const dpGold = Color(0xFFC9A227);
const dpMuted = Color(0xFF5C656C);
const dpSoft = Color(0xFFF3F6FB);

String complimentLabel(AppLocalizations l, String code) => switch (code) {
  'great_service' => l.complimentGreatService,
  'knew_the_way' => l.complimentKnewTheWay,
  'friendly' => l.complimentFriendly,
  'clean_car' => l.complimentCleanCar,
  'safe_driving' => l.complimentSafeDriving,
  'good_music' => l.complimentGoodMusic,
  _ => code,
};

/// "2026-11" → "november 2026" in the app's language.
String profileMonth(BuildContext context, String? month) {
  if (month == null) return '';
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final at = DateTime(
    int.tryParse(parts[0]) ?? 2000,
    int.tryParse(parts[1]) ?? 1,
  );
  return DateFormat.yMMMM(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(at);
}

/// Opens the sheet for [tripId] (one read, kept 5 min). Returns false when
/// the profile is off or could not be read: the caller opens its old page.
Future<bool> showDriverProfileSheet(
  BuildContext context, {
  required String tripId,
  required MatchedDriver driver,
}) async {
  if (!DriverProfileSettings.current.on) return false;
  final profile = await DriverProfiles.load(tripId);
  if (profile == null || !context.mounted) return false;
  // Rider guard: every sheet goes through MoveraSheet (one motion and barrier).
  await MoveraSheet.show<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => DriverProfileSheet(profile: profile, driver: driver),
  );
  return true;
}

/// Owner 2026-11-23 (P1v2): an outline icon for each compliment.
IconData complimentIcon(String code) => switch (code) {
  'great_service' => Icons.star_border_rounded,
  'clean_car' => Icons.auto_awesome_outlined,
  'knew_the_way' => Icons.map_outlined,
  'friendly' => Icons.sentiment_satisfied_alt_outlined,
  'safe_driving' => Icons.shield_outlined,
  'good_music' => Icons.music_note_outlined,
  _ => Icons.thumb_up_alt_outlined,
};

/// Owner 2026-11-23 (profile P1v2): the same information on a white sheet —
/// a plain photo with a soft shadow, name and since line, language and
/// city pills, one stats card, compliment chips with icons, the milestone
/// row and the latest review in a quote card.
class DriverProfileSheet extends StatelessWidget {
  const DriverProfileSheet({super.key, required this.profile, this.driver});

  final DriverPublicProfile profile;
  final MatchedDriver? driver;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = profile;
    final tag = Localizations.localeOf(context).toLanguageTag();
    final langs = p.languages
        .map((c) => profileLanguageNames[c] ?? c)
        .join(' · ');
    final number = NumberFormat.decimalPattern(tag);
    return Container(
      key: const ValueKey('driver-profile-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Material(
                color: const Color(0xFFF1F5F7),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  tooltip: l.close,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: dpNavy,
                  ),
                ),
              ),
            ),
            Container(
              key: const ValueKey('dp-photo'),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F061B44),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: DriverPhotoAvatar(
                driver: driver,
                radius: 50,
                fallback: Text(
                  p.firstName.isEmpty ? '?' : p.firstName.characters.first,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: dpNavy,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    p.firstName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: dpNavy,
                    ),
                  ),
                ),
                if (p.verified)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.verified_rounded,
                      color: dpBlue,
                      size: 22,
                      semanticLabel: l.dpVerified,
                    ),
                  ),
              ],
            ),
            if (p.sinceMonth != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l.dpSince(profileMonth(context, p.sinceMonth)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: dpMuted),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (langs.isNotEmpty) _pill(Icons.language_rounded, langs),
                if (p.city != null) _pill(Icons.place_outlined, p.city!),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              key: const ValueKey('dp-stats-card'),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7EBEE)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _kpi(number.format(p.tripCount), l.dpTrips),
                    const VerticalDivider(width: 1, color: Color(0xFFE7EBEE)),
                    _kpi(
                      p.rating == null
                          ? '–'
                          : NumberFormat('0.0', tag).format(p.rating),
                      l.dpRating,
                      star: p.rating != null,
                    ),
                    // Contract: years 0 shows only the since month.
                    if ((p.years ?? 0) > 0) ...[
                      const VerticalDivider(width: 1, color: Color(0xFFE7EBEE)),
                      _kpi('${p.years}', l.dpYears),
                    ],
                  ],
                ),
              ),
            ),
            if (p.compliments.isNotEmpty) ...[
              _title(l.dpWhatRidersSay),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in p.compliments)
                      _compliment(c.code, complimentLabel(l, c.code), c.count),
                  ],
                ),
              ),
            ],
            if (p.milestones.isNotEmpty) ...[
              _title(l.dpMilestones),
              for (final m in p.milestones)
                Padding(
                  key: ValueKey('dp-milestone-$m'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEAF2F8),
                          border: Border.all(color: const Color(0xFFBFD7EA)),
                        ),
                        child: Icon(
                          m == 'trips_1000'
                              ? Icons.emoji_events_outlined
                              : Icons.star_outline_rounded,
                          size: 20,
                          color: dpNavy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m == 'trips_1000'
                                  ? l.dpMilestoneTrips1000
                                  : l.dpMilestoneTopRating,
                              style: const TextStyle(
                                fontSize: 15,
                                color: dpNavy,
                              ),
                            ),
                            if (m == 'top_rating')
                              Text(
                                l.dpMilestoneTopRatingSub,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: dpMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (p.reviewText != null) ...[
              _title(l.dpLatestReview),
              Container(
                key: const ValueKey('dp-quote'),
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(
                      child: Text(
                        '“',
                        style: TextStyle(
                          fontSize: 44,
                          height: 0.9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC9D8E4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.reviewText!,
                            style: const TextStyle(
                              fontSize: 16,
                              color: dpNavy,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${p.reviewName ?? l.dpAnonymous} · ${profileMonth(context, p.reviewMonth)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: dpMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: dpMuted,
        ),
      ),
    ),
  );

  Widget _pill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFFE7EBEE)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: dpNavy),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: dpNavy),
          ),
        ),
      ],
    ),
  );

  Widget _compliment(String code, String label, int count) => Container(
    key: ValueKey('dp-compliment-$code'),
    padding: const EdgeInsets.fromLTRB(5, 5, 6, 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFFE7EBEE)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFF1F5F7),
          ),
          child: Icon(complimentIcon(code), size: 17, color: dpNavy),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: dpNavy),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F7),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: dpNavy,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _kpi(String value, String label, {bool star = false}) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: dpNavy,
              ),
            ),
            if (star)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: Color(0xFF055B95),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 13, color: dpMuted)),
      ],
    ),
  );
}

/// One compliment: the phone's own emoji (Text), the count and the words.
class ComplimentTile extends StatelessWidget {
  const ComplimentTile({
    super.key,
    required this.emoji,
    required this.label,
    this.count,
    this.selected = false,
  });

  final String emoji;
  final String label;
  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFE6F0FF) : dpSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: selected ? dpBlue : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        if (count != null) ...[
          const SizedBox(height: 2),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: dpNavy,
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: dpMuted),
        ),
      ],
    ),
  );
}
