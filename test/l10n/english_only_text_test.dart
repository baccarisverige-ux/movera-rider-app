import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'literal_scanner.dart';

/// Owner 2026-10-28: no English-only text on screen. Every string literal
/// in lib/ that reads as words must come from the translations (the ARB
/// files), or be one of the values below, each with the reason it is not
/// translated where it is written. The second half checks the stored
/// English values are translated where they are shown.

/// Files that hold data, not app text: the demo server (its texts play the
/// server's), the country list (checked below), zone names (written in
/// English, French and Swedish there), a map style and a web script.
const _dataFiles = {
  'lib/core/api/in_process_mock_client.dart',
  'lib/core/api/safety_mock_api.dart',
  'lib/core/realtime/mock_driver_pool.dart',
  'lib/features/auth/domain/phone_country_list.dart',
  'lib/core/config/rider_zones.dart',
  'lib/shared/styles/reference_map_style.dart',
  'lib/core/web/web_overlay_web.dart',
};

const _allowed = <String, Set<String>>{
  'names: brands, payment brands, languages in their own name, a place, '
      'the legacy demo profile seed it removes': {
    'Movera',
    'Movera Wallet',
    'Movera XL',
    'Movera Pet',
    'Apple Pay',
    'Google Pay',
    'Apple',
    'Google',
    'Visa',
    'Mastercard',
    'Visa, Mastercard',
    'English',
    'Français',
    'Svenska',
    'Solna centrum',
    'Ben Gleason',
  },
  'built-in catalog names, translated where shown (rideNameFor); Premium '
      'is the same word in English, French and Swedish': {
    'Comfort',
    'Premium',
    'Electric',
    'Priority',
    'Van',
    'Wheelchair',
    'Business',
    'Airport',
    'Kids seat',
    'Women driver',
    'Delivery',
  },
  'stored or sent in English, translated where shown (checked below)': {
    'Current location', 'Pickup location', 'Location off, set pickup',
    'Cash', 'Card', 'Wallet', 'Pay the driver in cash',
    'Pay from your balance', 'Pays when the search starts', 'Bags 3+',
    'Bags', 'Pet', 'Baby', 'Child', 'Family', 'Friend', 'Colleague',
    'Other', 'Called 112',
    // Ride notes of the built-in catalog (rideNoteFor).
    'Affordable and convenient rides', 'Newer cars with extra legroom',
    'Premium cars with top-rated drivers', 'More options, less waiting',
    'Cars for larger groups (6 people)', 'Quiet and fossil-free cars',
    'Pet-friendly rides', 'Groups and luggage',
    'Ramp or lift, driver helps on board',
    'Quiet ride, receipt for your company',
    'Fixed price, flight tracked, extra luggage',
    'Child seat already fitted', 'A woman behind the wheel',
    'Send a parcel across town',
    // Cancel reasons (CancellationReason.label, by id).
    'Pickup point is incorrect', 'I chose the wrong ride option',
    'I requested the ride by mistake', 'The wait is taking too long',
    'Destination needs to be changed',
    'Driver/ride details are not suitable', 'Plans changed',
    'Something else',
    // Ride check rows, headings, questions and answers (display…).
    'There was an accident', 'Accident', 'Is anyone hurt?',
    'Is the car in a safe place?', 'Is the other person OK?',
    'Someone is hurt or feels ill', 'Someone hurt', 'Who needs help?',
    'Me', 'The driver', 'Someone else', 'I feel unsafe', 'Unsafe',
    'Are you in danger right now?', 'The car broke down', 'Car problem',
    'Can you continue the trip?', 'I was left at the wrong place',
    'Wrong place', 'The driver asked me to leave the car',
    'Asked to leave', 'I asked the driver to stop', 'Stop',
    'I asked for this route', 'Route', 'Yes', 'No', 'Not sure',
  },
  'never shown: signal texts for the driver and the log': {
    "I'm on the way",
    'Your driver has arrived at the pickup point.',
  },
  'developer text and formats (the UI maps errors to translated words)': {
    'Request failed', 'Bearer', 'it is empty',
    'We accept Visa and Mastercard', 'd MMM yyyy',
    // Release composition refusing a build (transport_composition.dart).
    '" " is not an absolute URL', '" " is not https',
    '" " uses the reserved .invalid placeholder host',
    // CSS of the hidden safe-area probe (safe_area_insets_web.dart).
    'env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) '
        'env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px)',
  },
};

/// A caught error put on screen as it is (`Text('$e')`, `e.toString()`).
final _rawError = RegExp(
  r'''(?<![\w.])(Text|MoveraToast\.show|SnackBar)\([^;]*(\$\{?(e|error|err|exception)\b(?!\.message)|\b(e|error|err|exception)\.toString\(\))''',
);

/// Labels that are the same word in that language.
const _sameWord = {
  'fr': {'heading Accident'},
};

void main() {
  // The sources, read once as data (like the contract in other tests).
  final sources = <String, String>{
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') &&
          !file.path.contains('/generated/') &&
          !file.path.endsWith('.g.dart'))
        file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };
  final allowed = {for (final group in _allowed.values) ...group};

  test('every word in lib/ comes from the translations', () {
    final found = <String>[
      for (final entry in sources.entries)
        if (!_dataFiles.contains(entry.key))
          for (final literal in englishCandidates(entry.value))
            if (!allowed.contains(_words(literal.text)))
              '${entry.key}:${literal.line}: ${_words(literal.text)}',
    ];
    expect(sources.length, greaterThan(300));
    expect(
      found,
      isEmpty,
      reason:
          'English-only text: move it into lib/l10n/app_*.arb (en, fr, sv) '
          'or, when it is not shown, add it to _allowed with the reason.',
    );
  });

  test('no caught error is shown as it is', () {
    final found = <String>[
      for (final entry in sources.entries)
        for (final (i, line) in entry.value.split('\n').indexed)
          if (_rawError.hasMatch(line)) '${entry.key}:${i + 1}: $line',
    ];
    expect(found, isEmpty);
  });

  test('the scanner finds text and skips code', () {
    String? one(String src) {
      final hits = englishCandidates(src);
      return hits.isEmpty ? null : hits.single.text;
    }

    expect(one("final a = Text('Hello there');"), 'Hello there');
    expect(one("x(label: 'Cash');"), 'Cash');
    expect(one("x(t: 'Hi ' 'you \${name}');"), 'Hi you  ');
    expect(one("x('''Multi\nline text''');"), 'Multi\nline text');
    expect(englishCandidates("a ? 'Yes please' : 'No thanks';"), hasLength(2));
    expect(one("import 'package:a/b.dart';"), isNull);
    expect(one("throw StateError('Not a ride id');"), isNull);
    expect(one("AppLog.warning('ride.failed', extra: {'a': 'b c'});"), isNull);
    expect(one("final m = {'Content-Type': 'application/json'};"), isNull);
    expect(one("switch (v) { 'Cash' => 1, _ => 2 };"), isNull);
    expect(one("if (v == 'Some text') {}"), isNull);
    expect(one("// Text('In a comment')"), isNull);
    expect(one("final k = ValueKey('Save button');"), isNull);
    expect(one("final p = '/api/v1/trips/\$id/cancel';"), isNull);
    expect(one("final f = 'assets/images/car.webp';"), isNull);
    expect(_rawError.hasMatch("Text('\$error')"), isTrue);
    expect(_rawError.hasMatch('Text(e.toString())'), isTrue);
    expect(_rawError.hasMatch('Text(error.message)'), isFalse);
  });

  group('stored English is translated where shown', () {
    tearDown(() => L10n.use('en'));

    for (final code in ['fr', 'sv']) {
      test('$code: country names', () {
        final missing = [
          for (final country in PhoneCountries.all)
            if ((code == 'fr' ? country.fr : country.sv) == null) country.iso,
        ];
        expect(missing, isEmpty);
      });

      test('$code: labels the app keeps in English', () {
        L10n.use('en');
        final inEnglish = _shownLabels();
        L10n.use(code);
        final shown = _shownLabels();
        expect(shown.keys, inEnglish.keys);
        final untranslated = [
          for (final key in shown.keys)
            if (shown[key] == inEnglish[key] &&
                !(_sameWord[code]?.contains(key) ?? false))
              key,
        ];
        expect(untranslated, isEmpty);
      });
    }
  });
}

/// The labels the app stores in English, as [L10n.current] shows them.
Map<String, String> _shownLabels() => {
  for (final v in ['Cash', 'Card', 'Movera Wallet']) v: paymentLabelFor(v),
  for (final v in [
    'Pay the driver in cash',
    'Pay from your balance',
    'Pays when the search starts',
  ])
    v: paymentDetailFor('x', v),
  for (final v in ['Bags', 'Pet', 'Baby', 'Child']) v: RideNotes.labelFor(v),
  for (final v in ['Family', 'Friend', 'Colleague', 'Other'])
    v: relationshipLabel(v),
  for (final v in [
    'Current location',
    'Pickup location',
    'Location off, set pickup',
  ])
    v: L10n.place(v),
  for (final phase in CancelPhase.values)
    for (final reason in CancellationReason.forPhase(phase))
      'cancel ${reason.id}': reason.label,
  for (final row in rideCheckAllRows) ...{
    'row ${row.id.name}': row.displayLabel,
    'heading ${row.followUp.heading}': row.followUp.displayHeading,
    for (final question in row.followUp.questions) ...{
      'question ${question.id}': question.displayText,
      for (final option in question.options)
        'option ${option.id.name}': option.displayLabel,
    },
  },
  "I'm OK": RideCheckAnswer.ok(DateTime(2026)).summary,
  'Called 112': RideCheckAnswer.call112(DateTime(2026)).summary,
  for (final note in const [
    'Affordable and convenient rides',
    'Newer cars with extra legroom',
    'Quiet and fossil-free cars',
    'Send a parcel across town',
  ])
    note: rideNoteFor(note),
  for (final name in const [
    'Comfort',
    'Electric',
    'Priority',
    'Van',
    'Wheelchair',
    'Business',
    'Airport',
    'Kids seat',
    'Women driver',
    'Delivery',
  ])
    'category $name': rideNameFor(name),
  'Driver': const MatchedDriver(id: 'd', firstName: '').displayFirstName,
  'Loading': L10n.current.loaderTitle,
  'Device': L10n.current.sessionDeviceUnknown,
};

/// [text] with its runs of blanks as one space, trimmed.
String _words(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');
