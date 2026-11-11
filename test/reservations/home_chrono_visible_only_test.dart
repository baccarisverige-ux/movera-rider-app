import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R09 N6: the Home chrono checked the booked rides (which reads
/// `GET /trips/{id}` near pickup) every 30 s, also while another screen
/// covered Home and while the app was in the background.
class _CountingController extends ReservationController {
  _CountingController()
    : super(
        store: LocalReservationRepository(storage: MemoryReservationStorage()),
      );

  int checks = 0;

  @override
  Future<void> startLiveIfDue({DateTime? now}) async => checks++;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('checks at most every 60 s, only while Home is visible', (
    tester,
  ) async {
    final controller = _CountingController();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HomeReservationChrono(controller: controller)),
      ),
    );
    await tester.pump();
    expect(controller.checks, 1);

    await tester.pump(const Duration(seconds: 120));
    expect(controller.checks, 3, reason: 'one check per 60 s');

    // Another screen covers Home: no checks.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    final covered = controller.checks;
    await tester.pump(const Duration(minutes: 5));
    expect(controller.checks, covered);

    // Back on Home: checks again on the next tick.
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(controller.checks, covered + 1);

    // App in the background: no checks; after resume on the next tick.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final hidden = controller.checks;
    await tester.pump(const Duration(minutes: 5));
    expect(controller.checks, hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 30));
    expect(controller.checks, hidden + 1);
  });
}
