import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Pumps [screen] the way the app does (UI-11): the production ScreenUtil
/// setup from lib/app/screen_scale.dart, a [viewport] at 1 dpr and a
/// [textScale] applied like a system text-size setting.
Future<void> pumpMoveraScreen(
  WidgetTester tester,
  Widget screen, {
  Size viewport = const Size(390, 844),
  double textScale = 1,
  bool useAppNavigatorKey = false,
  Key? key,
  Locale? locale,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MoveraScreenUtilInit(
      key: key,
      builder: (_, __) => MaterialApp(
        navigatorKey: useAppNavigatorKey ? moveraNavigatorKey : null,
        // Round 4: a [locale] pumps the screen in that app language.
        locale: locale,
        localizationsDelegates: locale == null
            ? null
            : AppLocalizations.localizationsDelegates,
        supportedLocales: locale == null
            ? const [Locale('en', 'US')]
            : AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
}

/// Runs [body] while recording every FlutterError (not only the first) and
/// returns a one-line summary of each.
Future<List<String>> collectFlutterErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(_summarise(details));
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors.toSet().toList();
}

String _summarise(FlutterErrorDetails details) {
  final first = details.exceptionAsString().split('\n').first;
  final lines = details.toString().split('\n');
  final where = lines.indexWhere(
    (l) => l.contains('relevant error-causing widget was'),
  );
  final at = where < 0
      ? ''
      : ' at ${lines.skip(where + 1).take(2).map((l) => l.trim()).join(' ')}';
  final creator = RegExp(r'creator: ([^\n]+)').firstMatch(lines.join('\n'));
  final chain = creator == null
      ? ''
      : ' | ${creator.group(1)!.split(' ← ').take(6).join(' ← ')}';
  return '$first$at$chain';
}
