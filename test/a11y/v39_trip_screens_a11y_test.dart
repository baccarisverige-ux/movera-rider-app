import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/in_app_call_test.dart' show FakeApi, FakeEngine;

/// D5 (V39-7): the trip screens a rider uses under stress — chat, call,
/// in-trip panel, Ride check card, SOS (Safety kit) sheet — meet the
/// Android tap size (48), have a name on every tap target, keep text
/// contrast, and lay out at 200 % text without overflow.
class _Messages implements TripMessagesTransport {
  @override
  Future<List<ChatMessage>> list(String tripId) async => const [];

  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async => ChatMessage(
    text: text,
    sender: ChatMessageSender.rider,
    sentAt: DateTime.utc(2026, 11, 11),
    messageId: 'msg_1',
  );
}

class _NoCall implements TripCallTransport {
  @override
  Future<TripCall> call(String tripId) async => throw const ApiError(
    code: 'unavailable',
    message: 'no provider',
    statusCode: 503,
    reason: 'call_unavailable',
  );
}

void _noop() {}

typedef _Screen = Future<Widget> Function(WidgetTester tester);

SafetyController _safety() {
  final store = SafetyStore(
    local: PreferencesSafetyLocalDataSource(memoryOnly: true),
    remote: ApiSafetyRemoteDataSource(ApiClient(client: InProcessMockClient())),
  );
  return SafetyController(
    session: store,
    emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
  );
}

final _screens = <String, _Screen>{
  'chat': (tester) async {
    final chat = MessagesController.forRide('trp_a11y', transport: _Messages());
    addTearDown(chat.dispose);
    return Chat(
      driverName: 'Erik',
      rideId: 'trp_a11y',
      controller: chat,
      callTransport: _NoCall(),
    );
  },
  'call': (tester) async {
    final session = TripCallSession.outgoing(
      api: FakeApi(),
      engine: FakeEngine(),
      tripId: 'trp_a11y',
      side: 'rider',
    );
    await tester.runAsync(session.start);
    return TripCallScreen(session: session);
  },
  'in-trip': (tester) async => const Scaffold(
    body: RiderInTripPanel(
      destinationAddress: 'Hornsgatan 2, Stockholm',
      rideType: 'Movera',
      paymentMethod: 'Apple Pay',
      price: 259,
      driver: null,
      rideId: 'trp_a11y',
      onOpenProfile: _noop,
      onCall: _noop,
      onMore: _noop,
      onCancel: _noop,
    ),
  ),
  'ride check card': (tester) async {
    final safety = _safety();
    await tester.runAsync(safety.load);
    final rideCheck = RideCheckController.forSafety(safety);
    addTearDown(rideCheck.dispose);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'trp_a11y'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3429, 18.0496),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
    await tester.runAsync(
      () => rideCheck.open(RideCheckTrigger.longStop, rideId: 'trp_a11y'),
    );
    return Scaffold(
      body: RideCheckLayer(rideId: 'trp_a11y', controller: rideCheck),
    );
  },
  'SOS sheet': (tester) async {
    final safety = _safety();
    await tester.runAsync(safety.load);
    return Scaffold(
      body: RideSafetyKitSheet(
        rideId: 'trp_a11y',
        controller: safety,
        duringTrip: true,
      ),
    );
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    L10n.use('en');
    SharedPreferences.setMockInitialValues({});
    MessagesRepository.clearAllSessions();
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  Future<void> pump(
    WidgetTester tester,
    _Screen screen, {
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final child = await screen(tester);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: child,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final MapEntry(key: name, value: screen) in _screens.entries) {
    testWidgets('$name: tap targets are at least 48 x 48', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, screen);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await done(tester);
    });

    testWidgets('$name: every tap target has a name', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, screen);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await done(tester);
    });

    testWidgets('$name: text contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, screen);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
      await done(tester);
    });

    testWidgets('$name: 200 % text lays out without overflow', (tester) async {
      await pump(tester, screen, textScale: 2);
      expect(tester.takeException(), isNull);
      await done(tester);
    });
  }
}
