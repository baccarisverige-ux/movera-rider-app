import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_photo.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.5 §30: G9 chat not kept in the apps, G14 safety sheet
/// only during a trip, G2-D3 the driver's approved photo.

Map<String, dynamic> get _contract =>
    jsonDecode(File('contracts/contract.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    MessagesRepository.clearAllSessions();
    DriverPhotos.clear();
    DriverPhotos.debugApi = null;
    L10n.use('en');
  });

  group('G9 chat.appStorage', () {
    test('the trip ends: the chat is emptied, closed and not kept', () {
      final chat = MessagesRepository.forRide('trp_9');
      chat.ingest(
        ChatMessage(
          text: 'hi',
          sender: ChatMessageSender.driver,
          messageId: 'm1',
          sentAt: DateTime.utc(2026, 10, 30, 12),
        ),
      );
      expect(chat.messages, hasLength(1));

      MessagesController.closeRide('trp_9');

      // A screen still holding it sees it empty; a new look finds nothing.
      expect(chat.messages, isEmpty);
      expect(chat.closed, isTrue);
      final again = MessagesRepository.forRide('trp_9');
      expect(again.messages, isEmpty);
      expect(again.closed, isTrue);
    });

    test('no live ride any more: every chat is emptied', () {
      final a = MessagesRepository.forRide(
        'trp_a',
      )..ingest(const ChatMessage(text: 'x', sender: ChatMessageSender.driver));
      MessagesRepository.endAllRides();
      expect(a.messages, isEmpty);
      expect(MessagesRepository.forRide('trp_a').messages, isEmpty);
    });

    test('a chat push never becomes a Notifications line', () {
      final feed = NotificationsRepository();
      feed.ingest(
        PushPayload.fromMap({
          'kind': 'trip_message',
          'title': 'Message from your driver',
          'body': 'hi',
        }),
        read: false,
      );
      expect(feed.all(), isEmpty);
    });

    test('"New message" is the contract text in sv / fr / en', () {
      final texts = _contract['chat']['appStorage']['texts']['newMessage'];
      for (final lang in ['sv', 'fr', 'en']) {
        L10n.use(lang);
        expect(L10n.current.chatNewMessage, texts[lang]);
      }
    });

    test('Notifications: dates in the app language (one language per '
        'screen)', () {
      final feed = NotificationsRepository(
        now: () => DateTime(2026, 10, 30, 12),
      );
      feed.ingest(
        PushPayload.fromMap({
          'kind': 'trip_update',
          'title': 'x',
        }, sentAt: DateTime(2026, 10, 3, 8, 5)),
        read: true,
      );
      L10n.use('sv');
      expect(L10n.current.notification, 'Avisering');
      final sv = feed.all().single.time;
      L10n.use('fr');
      final fr = feed.all().single.time;
      expect(sv, isNot(fr));
      expect(fr, contains('oct'));
    });
  });

  group('G14 safety.onlyDuringTrip', () {
    Future<SafetyController> controller(RecordingEmergencyDialer dialer) async {
      final ctl = SafetyController(
        session: SafetyStore(
          local: PreferencesSafetyLocalDataSource(memoryOnly: true),
          remote: const UnservedSafetyRemoteDataSource(),
        ),
        emergency: EmergencyCallService(dialer: dialer),
      );
      await ctl.load();
      return ctl;
    }

    testWidgets('no trip: only "Call 112" (dialer, nothing sent) and Safety '
        'preferences', (tester) async {
      final dialer = RecordingEmergencyDialer();
      final ctl = (await tester.runAsync(() => controller(dialer)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RideSafetyKitSheet(controller: ctl)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.safetyCall112), findsOneWidget);
      expect(find.text(L10n.current.contact112), findsNothing);
      expect(find.text(L10n.current.shareTrip), findsNothing);
      expect(find.text(L10n.current.safetyPreferences), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('safety-call-112')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(dialer.calls, ['112']);
      expect(
        ctl.events.where((e) => e.kind == SafetyKind.sos),
        isEmpty,
        reason: 'nothing is sent to Movera without a trip',
      );
    });

    testWidgets('during a trip: SOS and Share trip', (tester) async {
      final ctl = (await tester.runAsync(
        () => controller(RecordingEmergencyDialer()),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideSafetyKitSheet(rideId: 'trp_1', controller: ctl),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('safety-sos')), findsOneWidget);
      expect(find.text(L10n.current.shareTrip), findsOneWidget);
      expect(find.byKey(const ValueKey('safety-call-112')), findsNothing);
    });

    testWidgets('checker LOW 9: while finding a driver (no driver yet) the '
        'kit offers only "Call 112"; with a driver, SOS', (tester) async {
      for (final assigned in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SafetyKitSheetRow(
                rideId: 'trp_s',
                driverAssigned: assigned,
              ),
            ),
          ),
        );
        await tester.tap(find.byType(SafetyKitSheetRow));
        await tester.pumpAndSettle();
        final sheet = tester.widget<RideSafetyKitSheet>(
          find.byType(RideSafetyKitSheet),
        );
        expect(sheet.duringTrip, assigned, reason: 'assigned=$assigned');
        expect(
          find.byKey(const ValueKey('safety-call-112')),
          assigned ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('safety-sos')),
          assigned ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    test('"Call 112" is the contract text; no demo words', () {
      final t = _contract['safety']['onlyDuringTrip']['texts']['call112'];
      for (final lang in ['sv', 'fr', 'en']) {
        L10n.use(lang);
        expect(L10n.current.safetyCall112, t[lang]);
        final arb = File('lib/l10n/app_$lang.arb').readAsStringSync();
        expect(arb.toLowerCase(), isNot(contains('in preview')));
        expect(arb.toLowerCase(), isNot(contains('en aperçu')));
      }
    });
  });

  group('G2-D3 driver photo', () {
    const path = '/api/v1/rider/trips/trp_7/driver-photo';
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );

    test('photoUrl is read from DriverSummary', () {
      final d = MatchedDriver.fromJson({
        'driverId': 'drv_1',
        'firstName': 'Sara',
        'photoUrl': path,
      })!;
      expect(d.photoUrl, path);
      expect(d.toJson()['photoUrl'], path);
    });

    test('loaded with the rider\'s bearer token; only the contract path; '
        'dropped when the trip ends', () async {
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'rider-token', refresh: 'r');
      final seen = <http.Request>[];
      DriverPhotos.debugApi = ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        tokens: tokens,
        client: MockClient((request) async {
          seen.add(request);
          return http.Response.bytes(
            png,
            200,
            headers: {'cache-control': 'private, no-store'},
          );
        }),
      );
      expect(await DriverPhotos.load('https://evil.example/x.png'), isNull);
      expect(seen, isEmpty);
      final bytes = await DriverPhotos.load(path);
      expect(bytes, png);
      expect(seen.single.url.path, path);
      expect(seen.single.headers['Authorization'], 'Bearer rider-token');
      expect(DriverPhotos.heldCount, 1);
      DriverPhotos.clear();
      expect(DriverPhotos.heldCount, 0);
      expect(DriverPhotos.cached(path), isNull);
    });

    test('404 driver_photo_unavailable: the Movera avatar stays', () async {
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'a', refresh: 'r');
      DriverPhotos.debugApi = ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        tokens: tokens,
        client: MockClient(
          (_) async => http.Response(
            '{"code":"not_found","reason":"driver_photo_unavailable"}',
            404,
          ),
        ),
      );
      expect(await DriverPhotos.load(path), isNull);
    });

    testWidgets('the avatar shows the photo once loaded', (tester) async {
      final tokens = MemoryTokenStore();
      await tester.runAsync(() => tokens.save(access: 'a', refresh: 'r'));
      DriverPhotos.debugApi = ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        tokens: tokens,
        client: MockClient((_) async => http.Response.bytes(png, 200)),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverPhotoAvatar(
            driver: MatchedDriver(id: 'd', firstName: 'Sara', photoUrl: path),
            radius: 22,
            fallback: Text('S'),
          ),
        ),
      );
      expect(find.text('S'), findsOneWidget);
      await tester.runAsync(() => DriverPhotos.load(path));
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverPhotoAvatar(
            key: ValueKey('again'),
            driver: MatchedDriver(id: 'd', firstName: 'Sara', photoUrl: path),
            radius: 22,
            fallback: Text('S'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('driver-photo-server')), findsOneWidget);
      expect(find.text('S'), findsNothing);
    });
  });
}
