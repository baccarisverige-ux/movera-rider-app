import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.64 §85 (owner 2026-11-11: "the language must arrive with
/// the receiver language and the translate when click on it must open
/// original language"): a message from the driver shows translated into the
/// rider's language; "See original" shows it as written, a second tap the
/// translation again; a failure shows the original with no notice.
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

  late List<http.Request> requests;
  late http.Response Function(Map<String, dynamic> body) translateAnswer;
  late bool autoTranslate;

  List<http.Request> translateRequests() => requests
      .where((r) => r.url.path == '/api/v1/trips/trp_1/messages/translate')
      .toList();

  Future<ApiClient> client() async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'a1', refresh: 'r1');
    return ApiClient(
      env: staging,
      tokens: tokens,
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/messages/options')) {
          return json({
            'quickReplies': const [],
            'quickRepliesOn': true,
            'maxLength': 2000,
            'sound': true,
            'sheetAutoOpen': 'new_message',
            'readAloudDefault': false,
            'translation': true,
            'autoTranslate': autoTranslate,
            'headerLine': const {'en': 'Problem? Use Support or SOS'},
          });
        }
        if (path.endsWith('/messages/translate')) {
          return translateAnswer(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
        }
        return json({
          'items': [
            {
              'messageId': 'msg_r',
              'tripId': 'trp_1',
              'from': 'rider',
              'text': 'Jag kommer',
              'lang': 'sv',
              'at': '2026-11-11T08:29:00Z',
            },
            {
              'messageId': 'msg_d',
              'tripId': 'trp_1',
              'from': 'driver',
              'text': 'Je suis devant la porte',
              'lang': 'fr',
              'at': '2026-11-11T08:30:00Z',
            },
            {
              'messageId': 'msg_a',
              'tripId': 'trp_1',
              'from': 'driver',
              'text': "I've arrived at the pickup point.",
              'auto': 'arrived',
              'lang': 'en',
              'at': '2026-11-11T08:31:00Z',
            },
          ],
          'nextCursor': null,
        });
      }),
    );
  }

  setUp(() {
    requests = [];
    autoTranslate = true;
    translateAnswer = (body) => json({
      'messageId': body['messageId'],
      'to': 'en',
      'text': "I'm in front of the door",
    });
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

  testWidgets('the driver\'s message arrives translated; "See original" '
      'shows it as written, a second tap the translation, one request', (
    tester,
  ) async {
    final controller = await pumpChat(tester);
    final asked = translateRequests();
    expect(asked, hasLength(1), reason: 'own and English messages: none');
    expect(jsonDecode(asked.single.body), {
      'messageId': 'msg_d',
      'to': 'en',
      'auto': true,
    });
    expect(find.text("I'm in front of the door"), findsOneWidget);
    expect(find.text('Je suis devant la porte'), findsNothing);
    expect(find.text('Jag kommer'), findsOneWidget);
    expect(find.text("I've arrived at the pickup point."), findsOneWidget);
    await tester.tap(find.text('See original'));
    await tester.pumpAndSettle();
    expect(find.text('Je suis devant la porte'), findsOneWidget);
    expect(find.text("I'm in front of the door"), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat-translate-msg_d')));
    await tester.pumpAndSettle();
    expect(find.text("I'm in front of the door"), findsOneWidget);
    expect(translateRequests(), hasLength(1));
    controller.dispose();
  });

  testWidgets('a stream message arrives translated too; the next chat screen '
      'shows the kept translation with no new request', (tester) async {
    translateAnswer = (body) => json({
      'messageId': body['messageId'],
      'to': 'en',
      'text': body['messageId'] == 'msg_s' ? 'Two minutes' : 'Door',
    });
    final controller = await pumpChat(tester);
    MessagesController.ingestStreamMessage('trp_1', {
      'messageId': 'msg_s',
      'tripId': 'trp_1',
      'from': 'driver',
      'text': 'Deux minutes',
      'lang': 'fr',
      'at': '2026-11-11T08:32:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.text('Two minutes'), findsOneWidget);
    expect(find.text('Deux minutes'), findsNothing);
    expect(translateRequests(), hasLength(2));
    controller.dispose();
    final again = await pumpChat(tester);
    expect(find.text('Two minutes'), findsOneWidget);
    expect(translateRequests(), hasLength(2));
    again.dispose();
  });

  testWidgets('503 coming_soon: the original, no notice; it stops asking for '
      'the trip', (tester) async {
    translateAnswer = (_) => json({
      'error': {
        'code': 'unavailable',
        'reason': 'coming_soon',
        'message': 'Translation coming soon',
      },
    }, 503);
    final controller = await pumpChat(tester);
    expect(find.text('Je suis devant la porte'), findsOneWidget);
    expect(find.text('Translation coming soon'), findsNothing);
    MessagesController.ingestStreamMessage('trp_1', {
      'messageId': 'msg_s2',
      'tripId': 'trp_1',
      'from': 'driver',
      'text': 'Allô ?',
      'at': '2026-11-11T08:33:00Z',
    });
    await tester.pumpAndSettle();
    expect(translateRequests(), hasLength(1));
    controller.dispose();
  });

  testWidgets('a server error: the original, no notice, no retry loop', (
    tester,
  ) async {
    translateAnswer = (_) => json({
      'error': {'code': 'internal', 'message': 'x'},
    }, 500);
    final controller = await pumpChat(tester);
    expect(find.text('Je suis devant la porte'), findsOneWidget);
    expect(find.text('Could not translate. Try again.'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(translateRequests(), hasLength(1));
    controller.dispose();
  });

  testWidgets('autoTranslate off (admin): nothing asked by itself; a tap '
      'still translates', (tester) async {
    autoTranslate = false;
    final controller = await pumpChat(tester);
    expect(translateRequests(), isEmpty);
    expect(find.text('Je suis devant la porte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-translate-msg_d')));
    await tester.pumpAndSettle();
    expect(find.text("I'm in front of the door"), findsOneWidget);
    expect(jsonDecode(translateRequests().single.body), {
      'messageId': 'msg_d',
      'to': 'en',
    });
    controller.dispose();
  });

  testWidgets('the trip ends: the translations go with the chat', (
    tester,
  ) async {
    final controller = await pumpChat(tester);
    expect(
      MessagesRepository.forRide('trp_1').translations.has('msg_d'),
      isTrue,
    );
    MessagesController.closeRide('trp_1');
    await tester.pumpAndSettle();
    expect(find.text("I'm in front of the door"), findsNothing);
    controller.dispose();
  });

  test('an older server (no autoTranslate) means off', () {
    final options = ChatOptions.fromJson(const {'translation': true});
    expect(options.autoTranslate, isFalse);
    expect(options.translatesByItself, isFalse);
  });
}
