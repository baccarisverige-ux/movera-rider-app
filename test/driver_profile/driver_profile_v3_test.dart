import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_profile_sheet.dart';
import 'package:movera_rider/features/ratings/domain/rating_tags.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.155 driver profile v3 (owner 2026-11-20 "Now build all";
/// contract.json#driverProfile): the new card, the profile sheet read once
/// and cached (no polling), the six compliment chips with the phone's own
/// emoji, the optional short review and "Show my first name".
const staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.staging.movera.example',
);

const profileJson = {
  'driverId': 'drv_1',
  'firstName': 'Ali',
  'verified': true,
  'photoUrl': null,
  'languages': ['sv', 'ar', 'en'],
  'city': 'Stockholm',
  'sinceMonth': '2023-03',
  'years': 3,
  'tripCount': 1284,
  'rating': 4.92,
  'compliments': [
    {'code': 'great_service', 'count': 42},
    {'code': 'clean_car', 'count': 18},
  ],
  'milestones': [
    {'code': 'trips_1000', 'reachedAt': '2026-03'},
  ],
  'latestReview': {
    'text': 'Punktlig och trygg.',
    'name': 'Sara',
    'month': '2026-11',
  },
};

const driver = MatchedDriver(
  id: 'drv_1',
  firstName: 'Ali',
  rating: 4.92,
  tripCount: 1284,
  vehicleMake: 'Toyota',
  vehicleModel: 'Corolla',
  vehicleColor: 'Vit',
  plate: 'ABC 123',
  yearsOnMovera: 3,
);

Widget app(Widget child, {String lang = 'sv'}) {
  L10n.use(lang);
  return MoveraScreenUtilInit(
    builder: (_, __) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));
  setUp(() {
    DriverProfiles.clear();
    DriverProfiles.reads = 0;
    DriverProfileSettings.current = DriverProfileSettings.defaults;
  });

  test('six chips in the contract order, all six may be picked', () {
    expect(RatingTags.aboutDriver, [
      'great_service',
      'knew_the_way',
      'friendly',
      'clean_car',
      'safe_driving',
      'good_music',
    ]);
    expect(RatingTags.maxPerRating, 6);
    expect(complimentEmoji.keys.toList(), RatingTags.aboutDriver);
  });

  test('the short review and the name choice go with the rating', () async {
    final sent = <Map<String, dynamic>>[];
    final repo = RideFeedbackRepository(
      api: ApiClient(
        env: staging,
        client: MockClient((r) async {
          sent.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'tripId': 'trp_1', 'from': 'rider', 'stars': 5}),
            201,
          );
        }),
      ),
    );
    await repo.submit(
      rideId: 'trp_1',
      rating: 5,
      tags: const ['great_service'],
      review: '  Punktlig.  ',
      showFirstName: false,
      idempotencyKey: 'k-aaaaaaaaaaaaaaaa',
    );
    expect(sent.single, {
      'stars': 5,
      'tags': ['great_service'],
      'review': 'Punktlig.',
      'reviewName': 'anonymous',
    });
  });

  testWidgets(
    'rating: emoji chips; with reviews on, the review box and Show my first name (on)',
    (tester) async {
      DriverProfileSettings.current = const DriverProfileSettings(
        on: true,
        reviews: true,
      );
      L10n.use('sv');
      addTearDown(() => L10n.use('en'));
      final reports = <RatingFeedback>[];
      await tester.pumpWidget(
        app(RideCompletedGiveReview(onFeedbackChanged: reports.add)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rating-star-5')));
      await tester.pumpAndSettle();
      expect(find.text('⭐'), findsOneWidget);
      expect(find.text('Utmärkt service'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rating-tag-great_service')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rating-review')), findsOneWidget);
      expect(find.text('Visa mitt förnamn'), findsOneWidget);
      expect(reports.last.showFirstName, isTrue);
      expect(reports.last.tags, ['great_service']);
    },
  );

  testWidgets(
    'card: plate, model + colour, Call and Message; a tap opens the profile once (cached)',
    (tester) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DriverProfiles.debugApi = ApiClient(
        env: staging,
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/rider/trips/trp_1/driver-profile');
          return http.Response(jsonEncode(profileJson), 200);
        }),
      );
      addTearDown(() => DriverProfiles.debugApi = null);
      var oldPage = 0;
      await tester.pumpWidget(
        app(
          DriverOnWayCard(
            driver: driver,
            rideId: 'trp_1',
            onOpenProfile: () => oldPage++,
            onCall: () {},
            now: DateTime(2026, 11, 20),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ABC 123'), findsOneWidget);
      expect(find.text('Toyota Corolla · Vit'), findsOneWidget);
      expect(find.text('1284 resor · Sedan 2023'), findsOneWidget);
      expect(find.text('Ring'), findsOneWidget);
      expect(find.text('Meddelande'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('driver-on-way-open-profile')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver-profile-sheet')),
        findsOneWidget,
      );
      expect(find.text('Vad resenärer säger'), findsOneWidget);
      expect(find.text('⭐'), findsOneWidget);
      expect(find.text('Svenska · العربية · English'), findsOneWidget);
      expect(find.textContaining('Sara · '), findsOneWidget);
      await tester.tap(find.byTooltip('Stäng'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('driver-on-way-open-profile')),
      );
      await tester.pumpAndSettle();
      expect(
        DriverProfiles.reads,
        1,
        reason: 'LOAD RULE: one read, then the 5 min copy',
      );
      expect(oldPage, 0);
    },
  );

  testWidgets(
    'profile off in the zone: the old simple page opens, nothing is read',
    (tester) async {
      DriverProfileSettings.current = const DriverProfileSettings(
        on: false,
        reviews: false,
      );
      var oldPage = 0;
      await tester.pumpWidget(
        app(
          DriverOnWayCard(
            driver: driver,
            rideId: 'trp_1',
            onOpenProfile: () => oldPage++,
            onCall: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('driver-on-way-open-profile')),
      );
      await tester.pumpAndSettle();
      expect(oldPage, 1);
      expect(DriverProfiles.reads, 0);
    },
  );

  testWidgets(
    'sheet: a hidden city and an anonymous review show no name and no city',
    (tester) async {
      final p = DriverPublicProfile.fromJson({
        ...profileJson,
        'city': null,
        'latestReview': {'text': 'Bra.', 'name': null, 'month': '2026-11'},
      });
      await tester.pumpWidget(app(DriverProfileSheet(profile: p), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Stockholm'), findsNothing);
      expect(find.textContaining('Anonymous · '), findsOneWidget);
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'emoji are text, no image files',
      );
    },
  );
}
