import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/driver_arriving/data/driver_arriving_repository.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/driver_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completion driver repository does not seed an identity', () {
    expect(const DriverRepository().current(), isNull);
  });

  test('legacy arriving adapter also stays empty without real driver data', () {
    final repository = DriverArrivingRepository();
    expect(repository.driver(), isNull);
    expect(repository.arrival(), isNull);
  });

  test('explicit driver profile remains available unchanged', () {
    const profile = DriverProfile(
      name: 'Real Driver',
      tagline: 'Verified',
      vehicle: 'Volvo EX30',
      plate: 'ABC 123',
      rideNumber: 'ride-real-1',
      ratingLabel: '4.9',
      completedAt: '2026-09-15 06:00',
    );

    final driver = const DriverRepository(current: profile).current();
    expect(driver, same(profile));
    expect(driver?.name, 'Real Driver');
    expect(driver?.plate, 'ABC 123');
  });

  testWidgets('completion UI shows honest state when driver is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            const MaterialApp(home: Scaffold(body: RideCompletedDriverInfo())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver details unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.person_search_outlined), findsOneWidget);
    expect(find.textContaining('Verified driver and vehicle'), findsOneWidget);
    expect(find.text('Merle Feeney'), findsNothing);
    expect(find.text('L - 2323 F'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
