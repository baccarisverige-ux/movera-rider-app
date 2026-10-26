import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-11: hand-rolled controls under 44 px, and a Back button a screen
/// reader announced with no name (Saved places, Add place). Measured as the
/// semantics rect, like the audit's scan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final screens = <String, (Widget Function(), String)>{
    'Saved places': (() => const SavedPlaces(), 'Back'),
    'Add place': (() => const AddPlace(), 'Back'),
    'Ride history': (
      () => RideHistory(
        reservations: ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
        ),
        onDemandReader: () async => const [],
      ),
      'Learn how it works',
    ),
    'Support': (
      () => SupportHome(loadRides: () async => const []),
      'View all rides',
    ),
  };

  for (final MapEntry(key: name, value: (build, label)) in screens.entries) {
    testWidgets('$name: "$label" is named and at least 44 x 44', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MoveraScreenUtilInit(builder: (_, __) => MaterialApp(home: build())),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final target = find.bySemanticsLabel(label);
        expect(target, findsOneWidget);
        final node = tester.getSemantics(target);
        expect(node.flagsCollection.isButton, isTrue);
        final rect = _globalRect(node);
        expect(rect.width, greaterThanOrEqualTo(43.99), reason: "$label width");
        expect(
          rect.height,
          greaterThanOrEqualTo(43.99),
          reason: "$label height",
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}

Rect _globalRect(SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    final transform = n.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}
