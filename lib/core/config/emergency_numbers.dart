import 'dart:convert';

import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One row of `RiderAppConfig.emergencyNumbers` (contract v0.18.57 §79,
/// `contract.json#emergencyNumbers.item`).
class EmergencyNumber {
  const EmergencyNumber({
    required this.kind,
    required this.number,
    required this.label,
  });

  static const kinds = {'police', 'ambulance', 'fire', 'general'};
  static final _pattern = RegExp(r'^\+?[0-9]{2,15}$');

  /// police | ambulance | fire | general.
  final String kind;

  /// Digits, optional leading +.
  final String number;

  /// `{ sv, fr, en }`.
  final Map<String, String> label;

  /// The label in the app language (English when missing).
  String get localLabel => label[L10n.code] ?? label['en'] ?? number;

  /// `emergencyNumbers.texts.callNumber`: "Call {label} {number}".
  String get callText {
    final template =
        EmergencyNumbers.callNumberTexts[L10n.code] ??
        EmergencyNumbers.callNumberTexts['en']!;
    return template
        .replaceAll('{label}', localLabel)
        .replaceAll('{number}', number);
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'number': number,
    'label': label,
  };

  static EmergencyNumber? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final number = json['number'];
    final label = json['label'];
    if (kind is! String || !kinds.contains(kind)) return null;
    if (number is! String || !_pattern.hasMatch(number)) return null;
    if (label is! Map) return null;
    final labels = <String, String>{};
    for (final code in const ['sv', 'fr', 'en']) {
      final text = label[code];
      if (text is String && text.trim().isNotEmpty) labels[code] = text;
    }
    if (labels.isEmpty) return null;
    return EmergencyNumber(kind: kind, number: number, label: labels);
  }
}

/// The country's emergency numbers (contract v0.18.57 §79): written by the
/// server into RiderAppConfig.emergencyNumbers. The last list received is
/// kept on the device; [fallback] (112) only when none was ever received.
abstract final class EmergencyNumbers {
  static const prefsKey = 'movera_rider_emergency_numbers_v1';

  /// `contract.json#emergencyNumbers.texts.callNumber`.
  static const callNumberTexts = {
    'sv': 'Ring {label} {number}',
    'fr': 'Appeler {label} {number}',
    'en': 'Call {label} {number}',
  };

  /// "A country with no default and nothing saved shows 112."
  static const fallback = [
    EmergencyNumber(
      kind: 'general',
      number: '112',
      label: {
        'sv': 'Nödnummer',
        'fr': 'Numéro d’urgence',
        'en': 'Emergency number',
      },
    ),
  ];

  static List<EmergencyNumber> current = fallback;

  /// True once a served list was taken (now or in an earlier session).
  /// Before that the screens keep their "112" texts.
  static bool get received => !identical(current, fallback);

  /// [row]'s "Call {label} {number}", or [legacy] (the old "Call 112"
  /// text) while no list was ever received.
  static String labelFor(EmergencyNumber row, String legacy) =>
      received ? row.callText : legacy;

  /// Tests: back to "never received".
  static void reset() => current = fallback;

  /// The main number: the SOS dials it.
  static EmergencyNumber get main => current.first;

  /// The rows after the main one (extra buttons on "SOS sent").
  static List<EmergencyNumber> get others => current.skip(1).toList();

  /// 1–6 valid rows, else null (the kept list stays).
  static List<EmergencyNumber>? parse(Object? json) {
    if (json is! List || json.isEmpty) return null;
    final rows = <EmergencyNumber>[];
    for (final item in json.take(6)) {
      final row = EmergencyNumber.fromJson(item);
      if (row != null) rows.add(row);
    }
    return rows.isEmpty ? null : List.unmodifiable(rows);
  }

  /// Takes the served list when valid and keeps it on the device.
  static Future<void> accept(Object? json) async {
    final rows = parse(json);
    if (rows == null) return;
    current = rows;
    try {
      final prefs = await PreferencesStore.load();
      await prefs.setString(
        prefsKey,
        jsonEncode([for (final r in rows) r.toJson()]),
      );
    } catch (error) {
      AppLog.warning(
        'emergency_numbers.write_failed',
        extra: {'error': error.toString()},
      );
    }
  }

  /// On start: the list kept from an earlier session, if any.
  static Future<void> restore() async {
    try {
      final prefs = await PreferencesStore.load();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final rows = parse(jsonDecode(raw));
      if (rows != null) current = rows;
    } catch (error) {
      AppLog.warning(
        'emergency_numbers.read_failed',
        extra: {'error': error.toString()},
      );
    }
  }
}
