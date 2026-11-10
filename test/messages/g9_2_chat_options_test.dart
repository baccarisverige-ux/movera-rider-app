import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.56 §78 (G9 part 2, rider): chat options, quick replies,
/// the header line, translate / "See original" / "coming soon", the auto
/// messages and the incoming-call push.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.test',
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final options = {
    'quickReplies': [
      {
        'id': 'coming_now',
        'text': {
          'sv': 'Jag kommer nu',
          'fr': "J'arrive tout de suite",
          'en': "I'm coming now",
        },
      },
      {
        'id': 'thanks',
        'text': {'sv': 'Tack!', 'fr': 'Merci !', 'en': 'Thanks!'},
      },
    ],
    'quickRepliesOn': true,
    'maxLength': 2000,
    'sound': true,
    'sheetAutoOpen': 'new_message',
    'readAloudDefault': false,
    'translation': true,
    'headerLine': {
      'sv': 'Problem? Använd Support eller SOS',
      'fr': 'Un problème ? Utilisez Support ou SOS',
      'en': 'Problem? Use Support or SOS',
    },
  };

  final arrived = {
    'messageId': 'msg_a',
    'tripId': 'trp_1',
    'from': 'driver',
    'text': "I've arrived",
    'at': '2026-11-10T08:30:00Z',
    'auto': 'arrived',
  };

  late List<http.Request> requests;
  late int translateStatus;

  Future<ApiClient> client() async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'a1', refresh: 'r1');
    return ApiClient(
      env: staging,
      tokens: tokens,
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/messages/options')) return json(options);
        if (path.endsWith('/messages/translate')) {
          if (translateStatus == 503) {
            return json({
              'error': {
                'code': 'unavailable',
                'reason': 'coming_soon',
                'message': 'Translation coming soon',
              },
            }, 503);
          }
          return json({
            'messageId': 'msg_a',
            'to': 'en',
            'text': 'I have arrived (translated)',
          });
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'messageId': 'msg_r1',
            'tripId': 'trp_1',
            'from': 'rider',
            'text': body['quickReplyId'] == 'coming_now'
                ? 'Jag kommer nu'
                : body['text'],
            'at': '2026-11-10T08:31:00Z',
            'quickReplyId': body['quickReplyId'],
          }, 201);
        }
        return json({
          'items': [arrived],
          'nextCursor': null,
        });
      }),
    );
  }

  setUp(() {
    requests = [];
    translateStatus = 200;
    MessagesRepository.clearAllSessions();
    L10n.use('en');
  });

  Future<MessagesController> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = await client();
    final controller = MessagesController.forRide(
      'trp_1',
      transport: ApiTripMessages(api: api),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Chat(
            driverName: 'Erik',
            rideId: 'trp_1',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the chat reads its options: header line, rider chips, the '
      "driver's automatic I've arrived, no report or block", (tester) async {
    final controller = await pumpChat(tester);
    expect(
      requests.map((r) => r.url.path),
      containsAll([
        '/api/v1/trips/trp_1/messages',
        '/api/v1/trips/trp_1/messages/options',
      ]),
    );
    expect(find.text('Problem? Use Support or SOS'), findsOneWidget);
    expect(find.textContaining('Report'), findsNothing);
    expect(find.textContaining('Block'), findsNothing);
    expect(find.text("I've arrived"), findsOneWidget);
    expect(controller.messages.single.auto, 'arrived');
    expect(find.text("I'm coming now"), findsOneWidget);
    expect(find.text('Thanks!'), findsOneWidget);

    await tester.tap(find.text("I'm coming now"));
    await tester.pumpAndSettle();
    final post = requests.lastWhere(
      (r) => r.method == 'POST' && r.url.path == '/api/v1/trips/trp_1/messages',
    );
    expect(jsonDecode(post.body), {
      'text': "I'm coming now",
      'quickReplyId': 'coming_now',
    });
    expect(controller.messages.last.quickReplyId, 'coming_now');
    controller.dispose();
  });

  testWidgets('Translate goes to the rider\'s own language; See original '
      'switches back', (tester) async {
    final controller = await pumpChat(tester);
    await tester.tap(find.text('Translate to English'));
    await tester.pumpAndSettle();
    final post = requests.lastWhere(
      (r) => r.url.path == '/api/v1/trips/trp_1/messages/translate',
    );
    expect(jsonDecode(post.body), {'messageId': 'msg_a', 'to': 'en'});
    expect(find.text('I have arrived (translated)'), findsOneWidget);
    expect(find.text("I've arrived"), findsNothing);

    await tester.tap(find.text('See original'));
    await tester.pumpAndSettle();
    expect(find.text("I've arrived"), findsOneWidget);
    expect(find.text('Translate to English'), findsOneWidget);

    // Translating again needs no new request.
    final before = requests.length;
    await tester.tap(find.text('Translate to English'));
    await tester.pumpAndSettle();
    expect(requests.length, before);
    expect(find.text('I have arrived (translated)'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('503 coming_soon says "Translation coming soon"', (tester) async {
    translateStatus = 503;
    final controller = await pumpChat(tester);
    await tester.tap(find.text('Translate to English'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Translation coming soon'), findsOneWidget);
    expect(find.text("I've arrived"), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    controller.dispose();
  });

  test('a trip-stream message raises the unread badge of that trip', () {
    final badge = MessagesController.forRide('trp_9');
    addTearDown(badge.dispose);
    expect(badge.unreadCount, 0);
    MessagesController.ingestStreamMessage('trp_9', {
      ...arrived,
      'tripId': 'trp_9',
    });
    expect(badge.unreadCount, 1);
    // The same event again (a resync) does not count twice.
    MessagesController.ingestStreamMessage('trp_9', {
      ...arrived,
      'tripId': 'trp_9',
    });
    expect(badge.unreadCount, 1);
  });

  test('the incoming-call push opens its trip and is no Notifications row', () {
    final push = PushPayload.fromMap({
      'kind': 'call_ringing',
      'tripId': 'trp_1',
      'callId': 'call_1',
      'deepLink': 'movera://trips/trp_1/call',
    });
    expect(push.isIncomingCall, isTrue);
    expect(push.routedRideId, 'trp_1');
    expect(push.destination, PushDestination.ride);
    final linkOnly = PushPayload.fromMap({
      'kind': 'call_ringing',
      'deepLink': 'movera://trips/trp_2/call',
    });
    expect(linkOnly.routedRideId, 'trp_2');
  });
}
