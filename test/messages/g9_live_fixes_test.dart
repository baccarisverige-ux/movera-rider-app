import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/chat_read_marks.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G9 live re-check 2026-11-02 (audits/live-g9-2026-11-02.md): the rider
/// fixes that need no owner decision.
class _Messages implements TripMessagesTransport {
  @override
  Future<List<ChatMessage>> list(String tripId) async => const [];
  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async => throw UnimplementedError();
}

class _Unavailable implements TripCallTransport {
  @override
  Future<TripCall> call(String tripId) async => throw const ApiError(
    code: 'unavailable',
    message: 'no provider',
    statusCode: 503,
    reason: 'call_unavailable',
  );
}

class _QuietRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _controller.stream;
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
  void dispose() => _controller.close();
}

ChatMessage _driver(String id, int minute) => ChatMessage(
  text: 'Driver $id',
  sender: ChatMessageSender.driver,
  sentAt: DateTime.utc(2026, 11, 2, 6, minute),
  messageId: id,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatReadMarks.resetForTest();
    L10n.use('en');
    MessagesRepository.clearAllSessions();
  });

  test('the decided call text in sv, fr and en', () {
    L10n.use('sv');
    expect(
      L10n.current.chatCallUnavailable,
      'Samtal kommer snart – använd chatten',
    );
    L10n.use('fr');
    expect(
      L10n.current.chatCallUnavailable,
      'Appels bientôt disponibles – utilisez le chat',
    );
    L10n.use('en');
    expect(
      L10n.current.chatCallUnavailable,
      'Calls coming soon – use the chat',
    );
  });

  testWidgets('the call answer never covers the write field or send button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = MessagesController.forRide('trp_1', transport: _Messages());
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Chat(
            driverName: 'Erik',
            rideId: 'trp_1',
            controller: chat,
            callTransport: _Unavailable(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Call'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    final notice = find.byKey(const ValueKey<String>('chat-call-notice'));
    expect(notice, findsOneWidget);
    expect(find.text('Calls coming soon – use the chat'), findsOneWidget);
    final field = tester.getRect(find.byType(TextField));
    expect(tester.getRect(notice).bottom, lessThanOrEqualTo(field.top));
    await tester.pump(const Duration(seconds: 5));
    expect(notice, findsNothing);
  });

  test('messages read before a reload are not counted again', () async {
    final before = MessagesRepository.forRide('trp_9')
      ..merge([_driver('m1', 1), _driver('m2', 2)]);
    expect(before.unreadCount, 2);
    before.markAllRead(DateTime.utc(2026, 11, 2, 6, 3));
    await pumpEventQueue();
    // A reload: nothing in memory, the marks read again from the device.
    ChatReadMarks.resetForTest();
    await ChatReadMarks.load();
    final after = MessagesRepository(rideId: 'trp_9')
      ..merge([_driver('m1', 1), _driver('m2', 2)]);
    expect(after.unreadCount, 0);
    after.merge([_driver('m3', 4)]);
    expect(after.unreadCount, 1, reason: 'a new message still counts');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ChatReadMarks.storageKey),
      isNot(contains('Driver')),
      reason: 'only a time is kept, never a message',
    );
    MessagesRepository.endRide('trp_9');
    await pumpEventQueue();
    expect(ChatReadMarks.of('trp_9'), isNull);
  });

  testWidgets('after the rating, an active trip opens instead of Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = 0;
    final keep = RideNavigator.openActiveTripAfterHome;
    RideNavigator.openActiveTripAfterHome = () async => opened++;
    addTearDown(() => RideNavigator.openActiveTripAfterHome = keep);
    AppScope.instance.ride
      ..rideId = 'trp_done'
      ..restoreFromBackend(RideStatus.tripCompleted);
    final realtime = _QuietRealtime();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1200, 2400),
        builder: (_, __) => MaterialApp(
          home: RideCompleted(
            status: RideStatus.tripCompleted,
            rideId: 'trp_done',
            realtime: realtime,
            persistOnDemandState: false,
            feedbackAvailableOnCompletion: true,
            showConnectionBanner: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey<String>('ride-completed-done')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(opened, 1);
  });
}
