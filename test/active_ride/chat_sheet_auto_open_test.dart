import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => unawaited(_events.close());
}

class _Chat implements TripMessagesTransport, TripChatExtras {
  _Chat(this.sheetAutoOpen);
  final String sheetAutoOpen;

  @override
  Future<ChatOptions> options(String tripId) async =>
      ChatOptions(sheetAutoOpen: sheetAutoOpen);
  @override
  Future<List<ChatMessage>> list(String tripId) async => const [];
  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<ChatMessage> sendQuickReply(
    String tripId,
    ChatQuickReply reply,
    String text, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<ChatTranslation> translate(
    String tripId,
    String messageId,
    String to,
  ) => throw UnimplementedError();
}

/// Rules REMINDERS row 29 (contract §78, owner Q82): a folded trip sheet
/// opens by itself on a NEW chat message only when
/// `CountryRules.chat.sheetAutoOpen` is `new_message`; with `off` it stays
/// folded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    MessagesRepository.clearAllSessions();
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<double> foldThenMessage(WidgetTester tester, String autoOpen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 86,
          currency: 'SEK',
          paymentMethod: 'Cash',
          rideId: 'chat-open',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: feed,
          persistRideSnapshot: false,
          tripMessages: _Chat(autoOpen),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final sheet = find.byType(Sheet);
    final resting = tester.getTopLeft(sheet).dy;

    // The rider folds the sheet to its low stop.
    await tester.fling(sheet, const Offset(0, 600), 2000);
    await tester.pump(const Duration(seconds: 1));
    final folded = tester.getTopLeft(sheet).dy;
    expect(folded, greaterThan(resting + 100), reason: 'the sheet folded');

    // A new message from the driver arrives on the trip stream.
    MessagesController.ingestStreamMessage('chat-open', {
      'messageId': 'msg_1',
      'tripId': 'chat-open',
      'from': 'driver',
      'text': 'I am outside',
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final after = tester.getTopLeft(sheet).dy;
    expect(resting, lessThan(folded));
    return after - resting;
  }

  testWidgets('sheetAutoOpen new_message: a new message opens the folded '
      'sheet to its resting stop', (tester) async {
    final offFromResting = await foldThenMessage(tester, 'new_message');
    expect(offFromResting.abs(), lessThan(2));
  });

  testWidgets('sheetAutoOpen off: a new message leaves the sheet folded', (
    tester,
  ) async {
    final offFromResting = await foldThenMessage(tester, 'off');
    expect(offFromResting, greaterThan(100));
  });
}
