import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/driver_profile/data/driver_profile_data.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';

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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DriverProfileSheet(profile: profile, driver: driver),
  );
  return true;
}

class DriverProfileSheet extends StatelessWidget {
  const DriverProfileSheet({super.key, required this.profile, this.driver});

  final DriverPublicProfile profile;
  final MatchedDriver? driver;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = profile;
    final langs = p.languages
        .map((c) => profileLanguageNames[c] ?? c)
        .join(' · ');
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
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
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  height: 120,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [dpNavy, Color(0xFF173A6B), dpBlue],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    tooltip: l.close,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
                Positioned(
                  top: 64,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE9C766), dpGold],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: DriverPhotoAvatar(
                        driver: driver,
                        radius: 42,
                        fallback: Text(
                          p.firstName.isEmpty
                              ? '?'
                              : p.firstName.characters.first,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: dpNavy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 70),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  p.firstName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: dpNavy,
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
                  style: const TextStyle(fontSize: 13, color: dpMuted),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (langs.isNotEmpty) _pill(Icons.translate_rounded, langs),
                if (p.city != null) _pill(Icons.place_outlined, p.city!),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _kpi(number.format(p.tripCount), l.dpTrips),
                  _kpi(
                    p.rating == null
                        ? '–'
                        : '${NumberFormat('0.0', Localizations.localeOf(context).toLanguageTag()).format(p.rating)} ★',
                    l.dpRating,
                  ),
                  // Contract: years 0 shows only the since month.
                  if ((p.years ?? 0) > 0) _kpi('${p.years}', l.dpYears),
                ],
              ),
            ),
            if (p.compliments.isNotEmpty) ...[
              _title(l.dpWhatRidersSay),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in p.compliments)
                      SizedBox(
                        width: 104,
                        child: ComplimentTile(
                          emoji: complimentEmoji[c.code]!,
                          label: complimentLabel(l, c.code),
                          count: c.count,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (p.milestones.isNotEmpty) ...[
              _title(l.dpMilestones),
              for (final m in p.milestones)
                ListTile(
                  dense: true,
                  leading: Text(
                    m == 'trips_1000' ? '\u{1F3C6}' : '\u{1F31F}',
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    m == 'trips_1000'
                        ? l.dpMilestoneTrips1000
                        : l.dpMilestoneTopRating,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: m == 'top_rating'
                      ? Text(l.dpMilestoneTopRatingSub)
                      : null,
                ),
            ],
            if (p.reviewText != null) ...[
              _title(l.dpLatestReview),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(14),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: dpSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“${p.reviewText}”',
                      style: const TextStyle(
                        fontSize: 15,
                        color: dpNavy,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p.reviewName ?? l.dpAnonymous} · ${profileMonth(context, p.reviewMonth)}',
                      style: const TextStyle(fontSize: 12, color: dpMuted),
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
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: dpNavy,
        ),
      ),
    ),
  );

  Widget _pill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: dpSoft,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: dpMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: dpNavy),
          ),
        ),
      ],
    ),
  );

  Widget _kpi(String value, String label) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: dpSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: dpNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: dpMuted)),
        ],
      ),
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
