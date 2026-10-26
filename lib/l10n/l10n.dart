import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

export 'package:movera_rider/l10n/generated/app_localizations.dart';

/// One app language the rider can pick (owner Q48/Q49).
class AppLanguage {
  const AppLanguage(this.code, this.name);

  /// `en`, `fr` or `sv` (`contract.json#languages`).
  final String code;

  /// The language's own name, so a rider finds it whatever is shown now.
  final String name;

  /// "FR · Français": the code and the name, as the picker lists them.
  String get label => '${code.toUpperCase()} · $name';
}

/// The app's languages and the one in use now.
///
/// Widgets read their strings with `context.l10n`. Code without a
/// [BuildContext] (formatters, domain labels) reads [L10n.current], which
/// [AppLanguageController] keeps equal to the app's locale.
abstract final class L10n {
  static const fallbackCode = 'en';

  static const languages = <AppLanguage>[
    AppLanguage('en', 'English'),
    AppLanguage('fr', 'Français'),
    AppLanguage('sv', 'Svenska'),
  ];

  static final Set<String> codes = {for (final l in languages) l.code};

  static AppLanguage languageOf(String code) => languages.firstWhere(
    (l) => l.code == code,
    orElse: () => languages.first,
  );

  /// [code] when the app ships it, else English.
  static String supported(String? code) {
    final value = code?.trim().toLowerCase() ?? '';
    return codes.contains(value) ? value : fallbackCode;
  }

  static String _code = fallbackCode;
  static AppLocalizations _current = lookupAppLocalizations(
    const Locale(fallbackCode),
  );

  /// The language in use now (`en`, `fr`, `sv`).
  static String get code => _code;

  /// The strings of the language in use now.
  static AppLocalizations get current => _current;

  /// Switches [current] (and intl's default locale for dates) to [code].
  static void use(String code) {
    final next = supported(code);
    _ensureDateSymbols();
    if (next == _code) return;
    _code = next;
    _current = lookupAppLocalizations(Locale(next));
    Intl.defaultLocale = next;
  }

  static bool _dateSymbolsReady = false;

  /// intl's month and weekday names for every app language. They ship with
  /// the package, so this is synchronous in practice.
  static void _ensureDateSymbols() {
    if (_dateSymbolsReady) return;
    _dateSymbolsReady = true;
    for (final l in languages) {
      initializeDateFormatting(l.code);
    }
  }

  /// [pattern] (an intl pattern such as `EEE, d MMM`) in the language in
  /// use now.
  static String formatDate(DateTime when, String pattern) {
    _ensureDateSymbols();
    return DateFormat(pattern, _code).format(when);
  }

  /// A place label as the rider reads it: the app's own English stand-ins
  /// for a pickup without a street address ("Current location",
  /// "Pickup location") are translated; real addresses pass through.
  static String place(String label) => switch (label) {
    'Current location' => current.currentLocation,
    'Location off, set pickup' => current.locationOffSetPickup,
    // rider-56: pickupLocationFallbackLabel, a pin with no street.
    'Pickup location' => current.pickupLocation,
    _ => label,
  };

  /// True when [label] is "Cash" in any app language.
  static bool isCashLabel(String label) {
    final value = label.trim().toLowerCase();
    return languages.any(
      (l) =>
          lookupAppLocalizations(Locale(l.code)).payCash.toLowerCase() == value,
    );
  }

  /// [value] with [digits] decimals and the app language's decimal mark:
  /// `1.2` in English, `1,2` in French and Swedish.
  static String formatDecimal(double value, {int digits = 1}) =>
      NumberFormat(digits > 0 ? '0.${'0' * digits}' : '0', _code).format(value);

  /// 24-hour clock time, `08:05`, as Movera shows it in every language.
  static String formatTime(DateTime when) =>
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
}

extension L10nContext on BuildContext {
  /// The strings of the app language.
  ///
  /// This is [L10n.current] on purpose: it is safe in `initState` and in
  /// callbacks after an async gap, where `Localizations.of` is not. When the
  /// language changes, [LanguageRebuild] rebuilds every screen, so nothing
  /// keeps showing the old language.
  AppLocalizations get l10n => L10n.current;
}

/// Rebuilds everything below it, open routes included, when [code]
/// changes (Q48: a new language applies at once, without restarting the
/// app or losing the ride on screen).
class LanguageRebuild extends StatefulWidget {
  const LanguageRebuild({super.key, required this.code, required this.child});

  final String code;
  final Widget child;

  @override
  State<LanguageRebuild> createState() => _LanguageRebuildState();
}

class _LanguageRebuildState extends State<LanguageRebuild> {
  @override
  void didUpdateWidget(LanguageRebuild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code == widget.code) return;
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
