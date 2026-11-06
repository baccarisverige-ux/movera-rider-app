import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/account_status/domain/rider_moderation.dart';
import 'package:movera_rider/features/account_status/presentation/account_status_screens.dart';
import 'package:movera_rider/features/ratings/domain/dont_match_again.dart';
import 'package:movera_rider/features/ratings/domain/rating_tags.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Fix job 10 (contract v0.18.40 §64, owner G16 Q16-1/Q16-4; G15 "Never
/// told", "No, only Support"): the 1-star "Don't match me with this driver
/// again" tick, and the rider level screens of v0.18.29 (warning banner,
/// paused screen with date, blocked screen with Support + Sign out).
/// Rule 36: fails on main (none of these exist).
Widget _app(Widget child) => MoveraScreenUtilInit(
  builder: (_, __) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Widget _screen(Widget child) => MoveraScreenUtilInit(
  builder: (_, __) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => DontMatchAgain.current = DontMatchAgain.defaults);

  test('RiderAppConfig.dontMatchAgain: on at 1 star by default', () {
    expect(DontMatchAgain.defaults.offeredAt(1), isTrue);
    expect(DontMatchAgain.defaults.offeredAt(2), isFalse);
    expect(
      DontMatchAgain.fromJson({'on': true, 'atStars': 2}).offeredAt(2),
      isTrue,
    );
    expect(DontMatchAgain.fromJson({'on': false}).offeredAt(1), isFalse);
    expect(DontMatchAgain.fromJson({'atStars': 7}).atStars, 1);
  });

  test('dontMatchAgain goes with the rating only when ticked', () async {
    final sent = <Map<String, dynamic>>[];
    final repository = RideFeedbackRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.staging.movera.example',
        ),
        client: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'tripId': 'trp_1', 'from': 'rider', 'stars': 1}),
            201,
          );
        }),
      ),
    );
    await repository.submit(
      rideId: 'trp_1',
      rating: 1,
      dontMatchAgain: true,
      idempotencyKey: 'k-aaaaaaaaaaaaaaaa',
    );
    await repository.submit(
      rideId: 'trp_1',
      rating: 1,
      idempotencyKey: 'k-bbbbbbbbbbbbbbbb',
    );
    expect(sent, [
      {'stars': 1, 'dontMatchAgain': true},
      {'stars': 1},
    ]);
  });

  testWidgets('the tick shows only at 1 star, more stars clear it, and it is '
      'reported with the feedback', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reports = <RatingFeedback>[];
    await tester.pumpWidget(
      _app(RideCompletedGiveReview(onFeedbackChanged: reports.add)),
    );
    await tester.pumpAndSettle();
    final tick = find.byKey(const ValueKey('dont-match-again'));
    expect(tick, findsNothing);
    await tester.tap(find.byIcon(Icons.star_rounded).at(0));
    await tester.pumpAndSettle();
    expect(tick, findsOneWidget);
    expect(find.text("Don't match me with this driver again"), findsOneWidget);
    await tester.tap(tick);
    await tester.pumpAndSettle();
    expect(reports.last.dontMatchAgain, isTrue);
    await tester.tap(find.byIcon(Icons.star_rounded).at(2));
    await tester.pumpAndSettle();
    expect(tick, findsNothing);
    expect(reports.last.dontMatchAgain, isFalse);
    expect(reports.last.stars, 3);
  });

  testWidgets('switched off by the admin: no tick at 1 star', (tester) async {
    DontMatchAgain.current = const DontMatchAgain(on: false, atStars: 1);
    await tester.pumpWidget(_app(const RideCompletedGiveReview()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_rounded).at(0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dont-match-again')), findsNothing);
  });

  test(
    'Rider.moderation is read from the profile and from a 403 projection',
    () {
      final paused = RiderModeration.fromJson({
        'level': 'paused',
        'reason': 'Unpaid fees',
        'until': '2026-11-13T10:00:00Z',
      });
      expect(paused.level, ModerationLevel.paused);
      expect(paused.blocksRiding, isTrue);
      expect(paused.until, DateTime.utc(2026, 11, 13, 10));
      expect(
        RiderModeration.fromJson({'level': 'warning', 'reason': 'x'})
            .blocksRiding,
        isFalse,
      );
      expect(
        RiderModeration.fromJson({'level': 'banned'}).blocksRiding,
        isTrue,
      );
      expect(RiderModeration.fromJson(null).level, ModerationLevel.none);
      expect(
        RiderModeration.fromRider({
          'riderId': 'r',
          'moderation': {'level': 'warning', 'reason': 'Be kind'},
        }).reason,
        'Be kind',
      );
    },
  );

  testWidgets('paused: title, reason, end date, Contact support, Sign out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        AccountStatusScreen(
          moderation: RiderModeration.fromJson({
            'level': 'paused',
            'reason': 'Unpaid fees',
            'until': '2026-11-13T10:00:00Z',
          }),
          onContactSupport: () {},
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your account is paused'), findsOneWidget);
    expect(find.text('Unpaid fees'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-status-until')), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('banned: blocked title, no date', (tester) async {
    await tester.pumpWidget(
      _screen(
        AccountStatusScreen(
          moderation: RiderModeration.fromJson({
            'level': 'banned',
            'reason': 'Suspected fraud',
          }),
          onContactSupport: () {},
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your account is blocked'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-status-until')), findsNothing);
  });

  testWidgets('warning: a banner with the reason; the app stays usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ModerationWarningBanner(
          moderation: RiderModeration.fromJson({
            'level': 'warning',
            'reason': 'Repeated cancellations',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Warning from Movera'), findsOneWidget);
    expect(find.text('Repeated cancellations'), findsOneWidget);
  });
}
