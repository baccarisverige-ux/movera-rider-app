import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingMockClient extends InProcessMockClient {
  final List<String?> idempotencyKeys = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      idempotencyKeys.add(request.headers['Idempotency-Key']);
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
  });

  tearDown(() {
    FindingDriverController.active = null;
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
  });

  test('in-flight finding submit is reused', () async {
    final booking = BookingCoordinator();
    final first = booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    final second = booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    expect(identical(first, second), isTrue);
    expect(await first, await second);
  });

  test('failed finding submit releases the lock for a later tap', () async {
    final mock = InProcessMockClient()..failNext = true;
    final booking = BookingCoordinator(api: ApiClient(client: mock));

    final failed = booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    await expectLater(failed, throwsA(isA<ApiError>()));

    final retried = await booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    expect(retried, isNotEmpty);
    expect(AppScope.instance.ride.rideId, retried);
  });

  test('failed finding retry reuses the same logical booking key', () async {
    final mock = RecordingMockClient()..failNext = true;
    final booking = BookingCoordinator(api: ApiClient(client: mock));

    Future<String> submit({double price = 259}) => booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: price,
      paymentMethod: 'Apple Pay',
    );

    await expectLater(submit(), throwsA(isA<ApiError>()));
    await submit();

    expect(mock.idempotencyKeys, hasLength(1));
    expect(mock.idempotencyKeys.single, isNotNull);
  });

  test('changed finding intent receives a new booking key', () async {
    final mock = RecordingMockClient()..failNext = true;
    final booking = BookingCoordinator(api: ApiClient(client: mock));

    await expectLater(
      booking.submitFinding(
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
      ),
      throwsA(isA<ApiError>()),
    );

    await booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 269,
      paymentMethod: 'Apple Pay',
    );

    expect(mock.idempotencyKeys, hasLength(1));
    expect(mock.idempotencyKeys.single, isNotNull);
  });

  test('failed scheduled retry reuses the same logical booking key', () async {
    final mock = RecordingMockClient()..failNext = true;
    final booking = BookingCoordinator(api: ApiClient(client: mock));

    Future<String> submit() => booking.requestBooking(
      rideType: 'economy',
      paymentMethod: 'Wallet',
      scheduledAt: '2026-09-13T10:00:00Z',
    );

    await expectLater(submit(), throwsA(isA<ApiError>()));
    await submit();

    expect(mock.idempotencyKeys, hasLength(2));
    expect(mock.idempotencyKeys[1], mock.idempotencyKeys.first);
  });

  test('in-flight scheduled booking is reused', () async {
    final booking = BookingCoordinator();
    final first = booking.requestBooking(
      rideType: 'economy',
      paymentMethod: 'Wallet',
      scheduledAt: '2026-09-13T10:00:00Z',
    );
    final second = booking.requestBooking(
      rideType: 'economy',
      paymentMethod: 'Wallet',
      scheduledAt: '2026-09-13T10:00:00Z',
    );
    expect(identical(first, second), isTrue);
    expect(await first, await second);
  });

  test('AppScope.booking is the singleton coordinator', () {
    expect(
      identical(AppScope.instance.booking, AppScope.instance.booking),
      isTrue,
    );
    expect(AppScope.instance.booking, isA<BookingCoordinator>());
  });

  test('second finding book refused while Finding UI is active', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final session = RideSession()..rideId = 'r-live';
    final controller = FindingDriverController(realtime: rt, ride: session);
    FindingDriverController.active = controller;
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.findingDriver,
      id: 'r-live',
    );
    final booking = BookingCoordinator();
    final refused = await booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    expect(refused, 'r-live');
    controller.dispose();
    rt.dispose();
  });

  test('in-flight coalesce still wins over finding-active refuse', () async {
    final booking = BookingCoordinator();
    final first = booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = FindingDriverController(
      realtime: rt,
      ride: RideSession(),
    );
    FindingDriverController.active = controller;
    final second = booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    expect(identical(first, second), isTrue);
    expect(await first, await second);
    controller.dispose();
    rt.dispose();
  });

  test(
    'BookingController shares AppScope.booking so a second tap is one ride',
    () async {
      final first = BookingController().submitFinding(
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
      );
      final second = BookingRepository().submitFinding(
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
      );
      expect(identical(first, second), isTrue);
      expect(await first, await second);
      expect(await first, AppScope.instance.ride.rideId);
    },
  );
}
