import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/api_trip_call.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/messages/presentation/trip_call.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.13.0 §22: the chat closes at drop-off and calls go through a
/// masked number (today 503 call_unavailable).
class _Messages implements TripMessagesTransport {
  Object? sendError;

  @override
  Future<List<ChatMessage>> list(String tripId) async => const [];

  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async {
    if (sendError case final error?) throw error;
    return ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      sentAt: DateTime.utc(2026, 10, 28),
      messageId: 'msg_1',
    );
  }
}

class _Call implements TripCallTransport {
  _Call(this.answer);
  final Object answer;
  int calls = 0;

  @override
  Future<TripCall> call(String tripId) async {
    calls += 1;
    if (answer case final TripCall call) return call;
    throw answer;
  }
}

const _closed = ApiError(
  code: 'invalid_transition',
  message: 'closed',
  statusCode: 409,
  reason: 'chat_closed',
);
const _unavailable = ApiError(
  code: 'unavailable',
  message: 'no provider',
  statusCode: 503,
  reason: 'call_unavailable',
);

void main() {
  setUp(() {
    L10n.use('en');
    MessagesRepository.clearAllSessions();
  });

  test('a 409 chat_closed send closes the chat; no more sends', () async {
    final server = _Messages()..sendError = _closed;
    final chat = MessagesController(
      store: MessagesRepository(),
      transport: server,
      rideId: 'trp_1',
    );
    expect(chat.canSendMessages, isTrue);
    expect(chat.send('hej'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(chat.isClosed, isTrue);
    expect(chat.canSendMessages, isFalse);
    expect(chat.send('igen'), isFalse);
  });

  Future<void> pumpChat(
    WidgetTester tester,
    MessagesController chat,
    TripCallTransport call,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Chat(
            driverName: 'Erik',
            rideId: 'trp_1',
            controller: chat,
            callTransport: call,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('after drop-off the input is disabled with a clear line', (
    tester,
  ) async {
    final chat = MessagesController.forRide('trp_1', transport: _Messages());
    addTearDown(chat.dispose);
    MessagesRepository.forRide('trp_1').markClosed();
    await pumpChat(tester, chat, _Call(_unavailable));
    expect(find.text('The chat is closed after the trip'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('503 call_unavailable says to use the chat, never dials', (
    tester,
  ) async {
    final chat = MessagesController.forRide('trp_1', transport: _Messages());
    addTearDown(chat.dispose);
    final call = _Call(_unavailable);
    await pumpChat(tester, chat, call);
    await tester.tap(find.byTooltip('Call'));
    await tester.pump();
    expect(call.calls, 1);
    expect(find.text("Calls aren't available yet – use the chat"), findsOne);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a proxy number is dialled; 409 closes the chat', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final dialled = <Uri>[];
    await callTripPeer(
      ctx,
      rideId: 'trp_1',
      transport: _Call(
        const TripCall(tripId: 'trp_1', proxyNumber: '+46101234567'),
      ),
      dial: (uri) async {
        dialled.add(uri);
        return true;
      },
    );
    expect(dialled, [Uri(scheme: 'tel', path: '+46101234567')]);

    await callTripPeer(ctx, rideId: 'trp_1', transport: _Call(_closed));
    await tester.pump();
    expect(MessagesRepository.forRide('trp_1').closed, isTrue);
    expect(find.text('The chat is closed after the trip'), findsOne);
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await callTripPeer(ctx, rideId: null, transport: null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Calls aren't available yet – use the chat"), findsOne);
    await tester.pump(const Duration(seconds: 5));
  });

  test('ApiTripCall posts to /trips/{id}/call and reads proxyNumber', () async {
    final seen = <http.Request>[];
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.staging.movera.example',
      ),
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(
          '{"tripId":"trp_1","proxyNumber":"+46101234567","expiresAt":"2026-10-28T10:00:00Z"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final call = await ApiTripCall(api: api).call('trp_1');
    expect(call.proxyNumber, '+46101234567');
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/trips/trp_1/call');
    expect(seen.single.headers['Idempotency-Key'], isNotNull);
  });
}
