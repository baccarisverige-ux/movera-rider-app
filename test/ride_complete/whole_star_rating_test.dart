import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';

/// Q38 / X20: ratings are whole stars, 1 to 5.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping the left half of a star gives that whole star', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ratings = <double>[];
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: RideCompletedGiveReview(onRatingChanged: ratings.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final third = find.byIcon(Icons.star_rounded).at(2);
    final box = tester.getRect(third);
    await tester.tapAt(Offset(box.left + box.width * 0.2, box.center.dy));
    await tester.pump();
    expect(ratings.last, 3);
    expect(ratings.every((r) => r == r.roundToDouble()), isTrue);
  });

  test('a half star is refused before it is sent', () async {
    final repository = RideFeedbackRepository(
      api: ApiClient(client: InProcessMockClient()),
    );
    await expectLater(
      repository.submit(rideId: 'ride-1', rating: 4.5, idempotencyKey: 'k-0123456789abcdef'),
      throwsArgumentError,
    );
  });
}
