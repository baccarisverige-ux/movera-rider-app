import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';

/// Contract v0.5.4: on the live wire the trip chat is
/// `POST /trips/{tripId}/messages { text }` (answer: the `Message`) and
/// `GET /trips/{tripId}/messages` (a `MessagePage`), polled because the
/// live transport never reads the event stream.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.test',
  );

  Map<String, dynamic> message({
    required String id,
    required String from,
    required String text,
    required String at,
  }) =>
      {'messageId': id, 'tripId': 'trp_1', 'from': from, 'text': text, 'at': at};

  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<ApiClient> client(
    List<http.Request> requests,
    Future<http.Response> Function(http.Request request) answer,
  ) async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'a1', refresh: 'r1');
    return ApiClient(
      env: staging,
      tokens: tokens,
      client: MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
  }

  test('a sent message POSTs /trips/{id}/messages with the headers of a '
      'mutation and { text }; the server copy replaces the local one', () async {
    final requests = <http.Request>[];
    final api = await client(requests, (request) async {
      expect(request.method, 'POST');
      return json(
        message(
          id: 'msg_9',
          from: 'rider',
          text: 'Are you close?',
          at: '2026-10-26T08:30:00Z',
        ),
        201,
      );
    });
    final controller = MessagesController(
      store: MessagesRepository(),
      transport: ApiTripMessages(api: api),
      rideId: 'trp_1',
    );
    addTearDown(controller.dispose);
    expect(controller.canSendMessages, isTrue);

    expect(controller.send('  Are you close?  '), isTrue);
    // Shown at once, before the server answers, honestly without a time.
    final local = controller.messages.single;
    expect(local.fromRider, isTrue);
    expect(local.delivery, ChatDelivery.sending);
    expect(local.sentAt, isNull);
    expect(local.messageId, isNull);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final sent = requests.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/trips/trp_1/messages');
    expect(sent.headers['Authorization'], 'Bearer a1');
    expect(sent.headers['X-Api-Version'], ApiClient.apiVersion);
    expect(sent.headers['Idempotency-Key'], hasLength(greaterThanOrEqualTo(16)));
    expect(jsonDecode(sent.body), {'text': 'Are you close?'});

    final confirmed = controller.messages.single;
    expect(confirmed.messageId, 'msg_9');
    expect(confirmed.delivery, ChatDelivery.sent);
    expect(confirmed.sentAt, DateTime.utc(2026, 10, 26, 8, 30));
    expect(confirmed.localId, local.localId);
    expect(controller.unreadCount, 0);
  });

  test('a failed send stays as not sent; the retry reuses the same '
      'Idempotency-Key and the second answer confirms it', () async {
    final requests = <http.Request>[];
    var failures = 0;
    final api = await client(requests, (request) async {
      if (requests.length == 1) {
        return json({'code': 'unavailable', 'message': 'down'}, 503);
      }
      return json(
        message(
          id: 'msg_10',
          from: 'rider',
          text: 'Hello',
          at: '2026-10-26T08:31:00Z',
        ),
        201,
      );
    });
    final controller = MessagesController(
      store: MessagesRepository(),
      transport: ApiTripMessages(api: api),
      rideId: 'trp_1',
    )..onSendFailed = (_, __) => failures += 1;
    addTearDown(controller.dispose);

    expect(controller.send('Hello'), isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(failures, 1);
    final failed = controller.messages.single;
    expect(failed.delivery, ChatDelivery.failed);
    expect(failed.text, 'Hello');

    await controller.retry(failed);

    expect(requests, hasLength(2));
    expect(
      requests[1].headers['Idempotency-Key'],
      requests[0].headers['Idempotency-Key'],
    );
    expect(requests[1].url.path, '/api/v1/trips/trp_1/messages');
    final confirmed = controller.messages.single;
    expect(confirmed.delivery, ChatDelivery.sent);
    expect(confirmed.messageId, 'msg_10');
  });

  /// Lets a MockClient answer land: its body is a byte stream, delivered
  /// through zero-length timers, so microtasks alone are not enough.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration.zero);
    }
  }

  testWidgets('polling lists /trips/{id}/messages on the interval, merges '
      'by messageId and counts driver and support messages unread',
      (tester) async {
    final requests = <http.Request>[];
    var listings = 0;
    // No expect inside the handler: it runs inside tester.pump, which
    // flutter_test's guarded expect refuses.
    final api = await client(requests, (request) async {
      listings += 1;
      return json({
        'items': [
          message(
            id: 'msg_1',
            from: 'driver',
            text: 'I am outside',
            at: '2026-10-26T08:29:00Z',
          ),
          if (listings >= 2)
            message(
              id: 'msg_2',
              from: 'support',
              text: 'Your driver is on the way',
              at: '2026-10-26T08:29:30Z',
            ),
        ],
        'nextCursor': null,
      });
    });
    final controller = MessagesController(
      store: MessagesRepository(),
      transport: ApiTripMessages(api: api),
      rideId: 'trp_1',
    );

    controller.startPolling(MessagesController.chatPollInterval);
    await settle(tester);

    // The first listing happens at once.
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v1/trips/trp_1/messages');
    expect(requests.single.url.queryParameters['limit'], '50');
    expect(requests.single.headers['Authorization'], 'Bearer a1');
    expect(requests.single.headers['X-Api-Version'], ApiClient.apiVersion);
    expect(controller.messages.map((m) => m.text), ['I am outside']);
    expect(controller.unreadCount, 1);

    await tester.pump(MessagesController.chatPollInterval);
    await settle(tester);
    expect(requests, hasLength(2));
    expect(controller.messages.map((m) => m.messageId), ['msg_1', 'msg_2']);
    expect(controller.messages.last.sender, ChatMessageSender.support);
    expect(controller.unreadCount, 2);

    // The same listing again adds nothing twice.
    await tester.pump(MessagesController.chatPollInterval);
    await settle(tester);
    expect(requests, hasLength(3));
    expect(controller.messages, hasLength(2));

    controller.markAllRead();
    expect(controller.unreadCount, 0);

    controller.stopPolling();
    await tester.pump(const Duration(seconds: 30));
    expect(requests, hasLength(3));
    controller.dispose();
  });

  test('a polled copy of the rider\'s own message does not double the '
      'local one, whichever answer comes first', () async {
    final requests = <http.Request>[];
    final api = await client(requests, (request) async {
      if (request.method == 'POST') {
        return json(
          message(
            id: 'msg_5',
            from: 'rider',
            text: 'On my way',
            at: '2026-10-26T08:32:00Z',
          ),
          201,
        );
      }
      return json({
        'items': [
          message(
            id: 'msg_5',
            from: 'rider',
            text: 'On my way',
            at: '2026-10-26T08:32:00Z',
          ),
        ],
        'nextCursor': null,
      });
    });
    final controller = MessagesController(
      store: MessagesRepository(),
      transport: ApiTripMessages(api: api),
      rideId: 'trp_1',
    );
    addTearDown(controller.dispose);

    expect(controller.send('On my way'), isTrue);
    // The listing lands before the send's own answer.
    await controller.refresh();
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.messageId, 'msg_5');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.delivery, ChatDelivery.sent);

    await controller.refresh();
    expect(controller.messages, hasLength(1));
  });

  test('the listing follows nextCursor and orders by server time', () async {
    final requests = <http.Request>[];
    final api = await client(requests, (request) async {
      final cursor = request.url.queryParameters['cursor'];
      if (cursor == null) {
        return json({
          'items': [
            message(
              id: 'msg_b',
              from: 'driver',
              text: 'second',
              at: '2026-10-26T08:02:00Z',
            ),
          ],
          'nextCursor': 'c2',
        });
      }
      expect(cursor, 'c2');
      return json({
        'items': [
          message(
            id: 'msg_a',
            from: 'driver',
            text: 'first',
            at: '2026-10-26T08:01:00Z',
          ),
        ],
        'nextCursor': null,
      });
    });

    final listed = await ApiTripMessages(api: api).list('trp_1');

    expect(requests, hasLength(2));
    expect(requests[1].url.queryParameters['cursor'], 'c2');
    expect(listed.map((m) => m.text), ['first', 'second']);
  });

  test('without a transport (the demo) nothing is sent or polled', () {
    final controller = MessagesController(store: MessagesRepository());
    addTearDown(controller.dispose);
    expect(controller.canSendMessages, isFalse);
    expect(controller.send('Hello'), isFalse);
    expect(controller.messages, isEmpty);
    controller.startPolling(MessagesController.chatPollInterval);
    expect(controller.isPolling, isFalse);
  });
}
