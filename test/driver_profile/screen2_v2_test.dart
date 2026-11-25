import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_profile_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: screen 2 ("driver on the way") as approved in
/// PROPOSAL-screen2-2026-11-23.html — sheet style, B2 driver card with EU
/// plate, inline driver message with the server's quick replies, games
/// row, arrived popup C1, ⋯ menu, profile P1v2, chat v2.
const _driver = MatchedDriver(
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

const _profileJson = {
  'driverId': 'drv_1',
  'firstName': 'Ali',
  'verified': true,
  'photoUrl': null,
  'languages': ['sv', 'en'],
  'city': 'Stockholm',
  'sinceMonth': '2023-03',
  'years': 3,
  'tripCount': 1284,
  'rating': 4.8,
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

class _Feed extends RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;
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
  void dispose() {}
}

class _Chat implements TripMessagesTransport, TripChatExtras {
  final sentChips = <String>[];
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
    sentAt: DateTime.now(),
    messageId: 'r_$text',
  );
  @override
  Future<ChatOptions> options(String tripId) async => const ChatOptions(
    quickRepliesOn: true,
    quickReplies: [
      ChatQuickReply(id: 'ok', text: {'sv': 'Okej!', 'en': 'OK!'}),
      ChatQuickReply(id: 'see', text: {'sv': 'Jag ser dig', 'en': 'I see you'}),
    ],
  );
  @override
  Future<ChatMessage> sendQuickReply(
    String tripId,
    ChatQuickReply reply,
    String text, {
    required String idempotencyKey,
  }) async {
    sentChips.add(reply.id);
    return ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      sentAt: DateTime.now(),
      messageId: 'q_${reply.id}',
    );
  }

  @override
  Future<ChatTranslation> translate(
    String tripId,
    String messageId,
    String to, {
    bool auto = false,
  }) async => throw UnimplementedError();
}

Widget _app(Widget home, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(390, 844),
    disableAnimations: reduceMotion,
  ),
  child: MoveraScreenUtilInit(
    builder: (_, __) => MaterialApp(
      locale: const Locale('sv'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpWaiting(WidgetTester tester) async {
  _phone(tester);
  AppScope.instance.ride.restoreFromBackend(
    RideStatus.driverAssigned,
    id: 'trp_1',
  );
  await tester.pumpWidget(
    _app(
      WaitingForDriver(
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Arlanda',
        pickupPosition: const LatLng(59.33, 18.07),
        destinationPosition: const LatLng(59.34, 18.06),
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'cash',
        driver: _driver,
        realtime: _Feed(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

MessagesController _messages(_Chat chat) => MessagesController(
  store: MessagesRepository.forRide('trp_1'),
  transport: chat,
  rideId: 'trp_1',
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('sv');
    MessagesRepository.clearAllSessions();
    DriverProfiles.clear();
    DriverProfiles.debugApi = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.staging.movera.example',
      ),
      client: MockClient(
        (_) async => http.Response(jsonEncode(_profileJson), 200),
      ),
    );
    DriverProfileSettings.current = DriverProfileSettings.defaults;
  });
  tearDown(() => L10n.use('en'));

  testWidgets('1: the sheet is full width, 28 px top, soft upward shadow', (
    tester,
  ) async {
    await _pumpWaiting(tester);
    final sheet = find.byKey(const ValueKey('waiting-sheet-card'));
    expect(sheet, findsOneWidget);
    expect(tester.getSize(sheet).width, 390);
    final box = tester.widget<DecoratedBox>(sheet).decoration as BoxDecoration;
    expect(
      box.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(28)),
    );
    expect(box.boxShadow!.single.offset.dy, lessThan(0));
  });

  testWidgets('2: B2 card — plain photo, EU plate top right with the model '
      'under it, round Ring / Chatt / ⋯ with labels, no chevron', (
    tester,
  ) async {
    await _pumpWaiting(tester);
    final card = find.byKey(const ValueKey('driver-on-way-card'));
    expect(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == dpGold,
        ),
      ),
      findsNothing,
    );
    final plate = find.byKey(const ValueKey('swedish-plate'));
    expect(find.descendant(of: plate, matching: find.text('S')), findsOne);
    expect(
      find.descendant(
        of: plate,
        matching: find.byKey(const ValueKey('eu-stars')),
      ),
      findsOneWidget,
    );
    final model = find.text('Toyota Corolla · Vit');
    expect(tester.getRect(plate).left, greaterThan(195));
    expect(
      tester.getRect(model).top,
      greaterThanOrEqualTo(tester.getRect(plate).bottom),
    );
    for (final key in ['waiting-call', 'waiting-chat', 'waiting-more']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, size.height, reason: key);
    }
    expect(find.descendant(of: card, matching: find.text('Ring')), findsOne);
    expect(find.descendant(of: card, matching: find.text('Chatt')), findsOne);
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('3: a driver message shows inline with the server quick '
      'replies; a chip sends and dismisses; the arrow opens the chat', (
    tester,
  ) async {
    _phone(tester);
    await tester.runAsync(loadDeferredScreens);
    final chat = _Chat();
    final messages = _messages(chat);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: DriverOnWayCard(
              driver: _driver,
              rideId: 'trp_1',
              onOpenProfile: () {},
              onCall: () {},
              onMore: () {},
              messages: messages,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('driver-msg-card')), findsNothing);
    messages.receive(
      ChatMessage(
        text: 'Jag står vid entrén, svart Volvo.',
        sender: ChatMessageSender.driver,
        sentAt: DateTime.now(),
        messageId: 'm1',
      ),
    );
    await tester.pump();
    await tester.pump();
    final inline = find.byKey(const ValueKey('driver-msg-card'));
    expect(inline, findsOneWidget);
    expect(find.text('Från Ali'), findsOneWidget);
    expect(find.text('Jag står vid entrén, svart Volvo.'), findsOneWidget);
    expect(find.byKey(const ValueKey('waiting-chat-unread')), findsOneWidget);
    await tester.tap(find.text('Okej!'));
    await tester.pump();
    await tester.pump();
    expect(chat.sentChips, ['ok']);
    expect(inline, findsNothing);
  });

  testWidgets('3b: the arrow on the inline message opens the chat', (
    tester,
  ) async {
    _phone(tester);
    await tester.runAsync(loadDeferredScreens);
    final messages = _messages(_Chat());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: DriverOnWayCard(
              driver: _driver,
              rideId: 'trp_1',
              onOpenProfile: () {},
              onCall: () {},
              messages: messages,
            ),
          ),
        ),
      ),
    );
    messages.receive(
      ChatMessage(
        text: 'Hej!',
        sender: ChatMessageSender.driver,
        sentAt: DateTime.now(),
        messageId: 'm1',
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('driver-msg-open')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(Chat), findsOneWidget);
  });

  testWidgets('4: the games row is at the bottom of this sheet too', (
    tester,
  ) async {
    await _pumpWaiting(tester);
    expect(
      find.byKey(const ValueKey('search-games-row'), skipOffstage: false),
      findsOneWidget,
    );
  });

  Future<void> pumpArrived(WidgetTester tester, {bool still = false}) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: DriverArrivedSheet(driver: _driver),
          ),
        ),
        reduceMotion: still,
      ),
    );
    await tester.pump();
  }

  testWidgets('5: arrived C1 — pin with rings, title, photo, plate, model, '
      'black pill', (tester) async {
    await pumpArrived(tester);
    expect(find.byKey(const ValueKey('arrived-pin')), findsOneWidget);
    expect(find.text('Ali är här'), findsOneWidget);
    expect(
      find.text('Din förare väntar vid upphämtningsplatsen.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swedish-plate')), findsOneWidget);
    expect(find.text('Vit Toyota Corolla'), findsOneWidget);
    expect(find.byKey(const ValueKey('arrived-photo')), findsOneWidget);
    expect(find.text('Jag är på väg'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('5b: reduce motion keeps the arrived rings still', (
    tester,
  ) async {
    await pumpArrived(tester, still: true);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('6: ⋯ menu — title left, Avboka resan the last red text row '
      'above Stäng', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RideDetailsSheet(
              pickupAddress: 'Sveavägen 44, Stockholm',
              destinationAddress: 'Stockholm Centralstation',
              rideType: 'Movera',
              price: 263,
              currency: Money.defaultCurrency,
              paymentMethod: 'cash',
              notes: RideNotes.empty,
              onCancelTrip: () {},
              onAddStop: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final title = find.text('Resedetaljer');
    expect(tester.getRect(title).left, lessThan(60));
    final cancel = find.byKey(const ValueKey('ride-details-cancel'));
    expect(cancel, findsOneWidget);
    expect(
      find.descendant(
        of: cancel,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    final close = find.text('Stäng');
    expect(
      tester.getRect(close).top,
      greaterThan(tester.getRect(cancel).bottom),
    );
    final text = tester.widget<Text>(
      find.descendant(of: cancel, matching: find.text('Avboka resan')),
    );
    expect(text.style?.color, const Color(0xFFB42318));
  });

  testWidgets('7: profile P1v2 — plain photo, stats card, icon chips, '
      'milestone row, quote card', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: DriverProfileSheet(
              profile: DriverPublicProfile.fromJson(_profileJson),
              driver: _driver,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('dp-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('dp-stats-card')), findsOneWidget);
    final chip = find.byKey(const ValueKey('dp-compliment-great_service'));
    expect(find.descendant(of: chip, matching: find.byType(Icon)), findsOne);
    expect(find.descendant(of: chip, matching: find.text('42')), findsOne);
    expect(find.text('⭐'), findsNothing);
    expect(find.byKey(const ValueKey('dp-milestone-trips_1000')), findsOne);
    expect(find.byKey(const ValueKey('dp-quote')), findsOneWidget);
    expect(find.text('Punktlig och trygg.'), findsOneWidget);
  });

  testWidgets('8: chat v2 — photo + plate header, round phone, white page, '
      'bubbles with the time inside, chips above the field, black send', (
    tester,
  ) async {
    _phone(tester);
    final messages = _messages(_Chat());
    messages.receive(
      ChatMessage(
        text: 'Hej! Jag är på väg.',
        sender: ChatMessageSender.driver,
        sentAt: DateTime(2026, 11, 23, 18, 22),
        messageId: 'm1',
      ),
    );
    MessagesRepository.forRide('trp_1').merge([
      ChatMessage(
        text: 'Toppen, tack!',
        sender: ChatMessageSender.rider,
        sentAt: DateTime(2026, 11, 23, 18, 23),
        messageId: 'm2',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        Chat(
          driverName: 'Ali',
          rideId: 'trp_1',
          driver: _driver,
          controller: messages,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-header-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('swedish-plate')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-call')), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );
    final rider = find.byKey(const ValueKey('chat-bubble-m2'));
    final driverBubble = find.byKey(const ValueKey('chat-bubble-m1'));
    BoxDecoration deco(Finder f) =>
        tester.widget<Container>(f).decoration! as BoxDecoration;
    expect(deco(rider).color, const Color(0xFF061B44));
    expect(deco(driverBubble).color, const Color(0xFFF1F5F7));
    expect(find.descendant(of: rider, matching: find.text('18:23')), findsOne);
    expect(find.text('Okej!'), findsOneWidget);
    expect(
      tester.getRect(find.text('Okej!')).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('chat-field'))).top),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-send')),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
  });

  for (final phase in [CancelPhase.matched, CancelPhase.inTrip]) {
    testWidgets('owner 2026-11-23: confirm sheet (${phase.name}) — black '
        'pill "Behåll resan" on top, red text action below', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CancelRideSheet(takingLonger: false, phase: phase),
            ),
          ),
        ),
      );
      await tester.pump();
      final keep = find.text('Behåll resan');
      final action = find.byKey(const ValueKey('cancel-ride-confirm'));
      expect(keep, findsOneWidget);
      expect(tester.getRect(keep).top, lessThan(tester.getRect(action).top));
      final button = tester.widget<TextButton>(action);
      expect(button.style?.backgroundColor?.resolve({}), isNull);
      expect(
        button.style?.foregroundColor?.resolve({}),
        const Color(0xFFB42318),
      );
    });
  }

  testWidgets('owner 2026-11-23: the menu holds "Flytta upphämtning" where '
      'the pickup may move; cancel stays the last red row', (tester) async {
    _phone(tester);
    var moved = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RideDetailsSheet(
              pickupAddress: 'Sveavägen 44, Stockholm',
              destinationAddress: 'Stockholm Centralstation',
              rideType: 'Movera',
              price: 263,
              paymentMethod: 'cash',
              notes: RideNotes.empty,
              onCancelTrip: () {},
              onMovePickup: () => moved++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final move = find.byKey(const ValueKey('ride-details-move-pickup'));
    expect(
      find.descendant(of: move, matching: find.text('Flytta upphämtning')),
      findsOneWidget,
    );
    expect(
      tester.getRect(move).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('ride-details-cancel'))).top,
      ),
    );
    await tester.tap(move);
    expect(moved, 1);
  });
}
