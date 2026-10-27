import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ratings/domain/rating_tags.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.9.0 (owner real-data decision, part 3): the rider rates with
/// stars, optional tags from the fixed list and an optional comment.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  test('the tag codes are contract.json#ratings.tags.aboutDriver', () {
    expect(RatingTags.aboutDriver, [
      'clean_car',
      'friendly',
      'safe_driving',
      'good_music',
      'knew_the_way',
    ]);
  });

  test(
    'stars, tags and a trimmed comment go to POST /trips/{id}/rating',
    () async {
      final sent = <Map<String, dynamic>>[];
      final repository = RideFeedbackRepository(
        api: ApiClient(
          env: staging,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/trips/trp_1/rating');
            sent.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({'tripId': 'trp_1', 'from': 'rider', 'stars': 4}),
              201,
            );
          }),
        ),
      );
      await repository.submit(
        rideId: 'trp_1',
        rating: 4,
        tags: const ['clean_car', 'friendly'],
        comment: '  Very calm driver  ',
        idempotencyKey: 'k-aaaaaaaaaaaaaaaa',
      );
      await repository.submit(
        rideId: 'trp_1',
        rating: 5,
        comment: '   ',
        idempotencyKey: 'k-bbbbbbbbbbbbbbbb',
      );
      expect(sent, [
        {
          'stars': 4,
          'tags': ['clean_car', 'friendly'],
          'comment': 'Very calm driver',
        },
        {'stars': 5},
      ]);
    },
  );

  test('a tag from another list, a repeated tag or a long comment is refused '
      'before it is sent', () async {
    final repository = RideFeedbackRepository(
      api: ApiClient(
        env: staging,
        client: MockClient((_) async => fail('nothing may be sent')),
      ),
    );
    Future<void> send({List<String> tags = const [], String? comment}) =>
        repository.submit(
          rideId: 'trp_1',
          rating: 3,
          tags: tags,
          comment: comment,
          idempotencyKey: 'k-aaaaaaaaaaaaaaaa',
        );
    await expectLater(send(tags: const ['polite']), throwsArgumentError);
    await expectLater(
      send(tags: const ['friendly', 'friendly']),
      throwsArgumentError,
    );
    await expectLater(send(comment: 'x' * 2001), throwsArgumentError);
  });

  testWidgets('tags and the comment appear after a star and are reported', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reports = <RatingFeedback>[];
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          locale: const Locale('sv'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RideCompletedGiveReview(onFeedbackChanged: reports.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rating-tags')), findsNothing);
    final fourth = find.byIcon(Icons.star_rounded).at(3);
    await tester.tap(fourth);
    await tester.pumpAndSettle();
    expect(find.text('Ren bil'), findsOneWidget);
    expect(find.text('Hittade rätt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rating-tag-safe_driving')));
    await tester.tap(find.byKey(const ValueKey('rating-tag-clean_car')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rating-comment')),
      'Lugn resa',
    );
    await tester.pumpAndSettle();
    final last = reports.last;
    expect(last.stars, 4);
    // In the contract's order, whatever order they were tapped in.
    expect(last.tags, ['clean_car', 'safe_driving']);
    expect(last.sentComment, 'Lugn resa');
    await tester.tap(find.byKey(const ValueKey('rating-tag-clean_car')));
    await tester.pumpAndSettle();
    expect(reports.last.tags, ['safe_driving']);
  });
}
