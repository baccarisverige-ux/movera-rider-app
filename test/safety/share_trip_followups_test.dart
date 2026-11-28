// Share my trip follow-ups (GO review of rider PR #713, merged 305c31cd):
// seven gaps, each test failed on main before the fix.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/share_trip_actions.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/presentation/share_trip_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.example.test',
);
const _url = 'https://share.example.test/s/AbCdEfGhIjKlMnOpQrStUv';
const _sharePath = '/api/v1/rider/trips/t1/share';

/// A stand-in for the server's share and contact routes.
class _Server {
  final calls = <String>[];
  final keys = <String?>[];
  bool ended = false;
  bool loseNextAnswer = false;
  final byKey = <String, Map<String, dynamic>>{};
  Map<String, dynamic> contacts = {'items': <Object>[], 'updatedAt': null};
  final links = <Map<String, dynamic>>[];
  bool zoneOff = false;
  bool deleteFails = false;

  Completer<void>? holdGet;

  Future<http.Response> answer(http.Request request) async {
    calls.add('${request.method} ${request.url.path}');
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path.endsWith('/emergency-contacts')) {
      if (request.method == 'PUT') {
        contacts = {
          ...jsonDecode(request.body) as Map<String, dynamic>,
          'updatedAt': '2026-11-16T08:00:00Z',
        };
      }
      return json(contacts);
    }
    if (request.url.path == _sharePath) {
      if (request.method == 'POST') {
        final key = request.headers['idempotency-key'];
        keys.add(key);
        if (ended) {
          return json({'state': 'ended', 'reason': 'share_ended'}, 410);
        }
        final replay = key == null ? null : byKey[key];
        if (replay != null) return json({...replay, 'url': _url}, 201);
        if (zoneOff) {
          return json({
            'code': 'forbidden',
            'reason': 'share_trip_off',
            'message': 'off',
            'requestId': 'r',
          }, 403);
        }
        final link = {
          'shareId': 'sh_${links.length + 1}',
          'tripId': 't1',
          'createdAt': '2026-11-16T08:00:00Z',
          'expiresAt': '2099-01-01T00:00:00Z',
          'endsAtDropoff': true,
        };
        links.add(link);
        if (key != null) byKey[key] = link;
        if (loseNextAnswer) {
          loseNextAnswer = false;
          return json({'code': 'unavailable', 'message': 'lost'}, 503);
        }
        return json({...link, 'url': _url}, 201);
      }
      if (request.method == 'DELETE') {
        if (deleteFails) {
          return json({'code': 'unavailable', 'message': 'no'}, 503);
        }
        links.clear();
        return http.Response('', 204);
      }
      final hold = holdGet;
      final listed = [...links];
      if (hold != null) await hold.future;
      return json({'items': listed});
    }
    return json({'code': 'not_found', 'message': 'no'}, 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _Server server;
  late SafetyController safety;
  late List<Uri> sms;
  late List<String> shared;
  late PreferencesSafetyLocalDataSource local;

  SafetyController controllerOn(PreferencesSafetyLocalDataSource store) =>
      SafetyController(
        session: SafetyStore(
          local: store,
          remote: ContractContactsRemoteDataSource(
            ApiClient(client: MockClient(server.answer), env: _staging),
          ),
        ),
        emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerFeatures.clear();
    server = _Server();
    sms = [];
    shared = [];
    local = PreferencesSafetyLocalDataSource(memoryOnly: true);
    safety = controllerOn(local);
    SafetyController.sharedForTest = safety;
    ShareTripActions.launcher = (uri) async {
      sms.add(uri);
      return true;
    };
    ShareTripActions.sharer = (text) async => shared.add(text);
  });

  tearDown(() {
    SafetyController.sharedForTest = null;
    ShareTripActions.reset();
    ServerFeatures.clear();
  });

  Future<void> addAnna({bool shareTrips = true}) async {
    await safety.load();
    await safety.addContact(
      name: 'Anna',
      phone: '0701740661',
      shareTrips: shareTrips,
    );
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareTripSheet(rideId: 't1', controller: safety),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> liveLink(String id) => {
    'shareId': id,
    'tripId': 't1',
    'createdAt': '2026-11-16T08:00:00Z',
    'expiresAt': '2099-01-01T00:00:00Z',
    'endsAtDropoff': true,
  };

  /// A controller whose kept Trip share setting is [prefs] (movera-server
  /// keeps no Safety settings, so the phone's own copy is what counts).
  Future<SafetyController> withPrefs(SafetyPreferences prefs) async {
    await local.load();
    await local.save(SafetyCache(preferences: prefs));
    final next = controllerOn(local);
    await next.load();
    return next;
  }

  // 1: "Automatically share every ride" did nothing on movera-server.
  test('1: auto-share opens the Share trip sheet once at trip start on '
      'movera-server, and makes no link itself', () async {
    var opened = 0;
    Future<void> open() async => opened++;
    final auto = await withPrefs(
      const SafetyPreferences(
        tripShareEnabled: true,
        tripShareMode: TripShareMode.auto,
      ),
    );
    expect(auto.preferences.tripShareMode, TripShareMode.auto);
    expect(await auto.autoShareRide('t1', openSheet: open), isNull);
    expect(await auto.autoShareRide('t1', openSheet: open), isNull);
    expect(opened, 1, reason: 'once per trip');
    expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
    // Manual mode, or Trip share off: no sheet.
    final manual = await withPrefs(
      const SafetyPreferences(tripShareEnabled: true),
    );
    await manual.autoShareRide('t2', openSheet: open);
    final off = await withPrefs(
      const SafetyPreferences(tripShareMode: TripShareMode.auto),
    );
    await off.autoShareRide('t3', openSheet: open);
    expect(opened, 1);
  });

  test('1: the Trip share ticks count only while Trip share is on; a '
      'contact with shareTrips on always counts', () async {
    Future<List<String>> recipients({required bool enabled}) async {
      server.contacts = {'items': <Object>[], 'updatedAt': null};
      final ctl = await withPrefs(SafetyPreferences(tripShareEnabled: enabled));
      await ctl.addContact(name: 'Anna', phone: '0701740661');
      await ctl.addContact(name: 'Bo', phone: '0701740662', shareTrips: true);
      final anna = ctl.contacts.firstWhere((c) => c.name == 'Anna').id;
      await local.save(
        (await local.load())
          ..preferences = ctl.preferences.copyWith(
            tripShareEnabled: enabled,
            tripShareContactIds: [anna],
          ),
      );
      final next = controllerOn(local);
      await next.load();
      expect(next.preferences.tripShareContactIds, [anna]);
      return [
        for (final id in next.tripShareRecipients)
          next.contacts.firstWhere((c) => c.id == id).name,
      ];
    }

    expect(await recipients(enabled: false), ['Bo']);
    expect(await recipients(enabled: true), ['Anna', 'Bo']);
  });

  // 2: after a reinstall the server has a live link the phone has no URL for.
  testWidgets('2: Stop sharing shows while the server lists a live link '
      'with no URL on this phone', (tester) async {
    await tester.runAsync(safety.load);
    server.links.add(liveLink('sh_1'));
    await pumpSheet(tester);
    await settle(tester);
    expect(safety.shareFor('t1')?.isActive, isTrue);
    expect(safety.shareFor('t1')?.canSend, isFalse);
    expect(find.byKey(const ValueKey('share-trip-stop')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('share-trip-stop')));
    expect(server.calls, contains('DELETE $_sharePath'));
  });

  // 3: a GET sent before a POST must not wipe the POST's new link.
  test('3: a late GET answer does not replace a link made after it was '
      'sent', () async {
    await safety.load();
    final hold = Completer<void>();
    server.holdGet = hold;
    final refresh = safety.refreshShare('t1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    server.holdGet = null;
    expect(await safety.shareLink('t1'), _url);
    hold.complete();
    await refresh;
    expect(safety.shareFor('t1')?.canSend, isTrue);
    expect(safety.shareFor('t1')?.url, _url);
    expect(safety.shareEndedFor('t1'), isFalse);
    expect((await local.load()).shares['t1']?.url, _url);
  });

  // 3b (#717 NO-GO): a GET sent before "Stop sharing" and answered after
  // it must not bring the stopped link back as live.
  test('3b: a late GET answer does not revive a link stopped after it was '
      'sent', () async {
    await safety.load();
    expect(await safety.shareLink('t1'), _url);
    final hold = Completer<void>();
    server.holdGet = hold;
    final refresh = safety.refreshShare('t1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    server.holdGet = null;
    await safety.stopShare('t1');
    expect(server.calls, contains('DELETE $_sharePath'));
    hold.complete();
    await refresh;
    expect(safety.shareFor('t1')?.canSend, isNot(isTrue));
    expect(safety.shareEndedFor('t1'), isTrue);
    expect((await local.load()).shares['t1']?.canSend, isNot(isTrue));
  });

  // 4: no off-palette grey in the sheet.
  testWidgets('4: every text in the sheet is Movera ink #12201C', (
    tester,
  ) async {
    await tester.runAsync(() => addAnna());
    await pumpSheet(tester);
    await tap(tester, find.byKey(const ValueKey('share-trip-with')));
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ShareTripSheet),
        matching: find.byType(Text),
      ),
    );
    var checked = 0;
    for (final text in texts) {
      final color = text.style?.color;
      if (color == null) continue;
      checked++;
      expect(
        color.toARGB32() & 0xFFFFFF,
        0x12201C,
        reason: '"${text.data}" is ${color.toARGB32().toRadixString(16)}',
      );
    }
    expect(checked, greaterThanOrEqualTo(4));
  });

  // 5: hidden outside the live statuses, so no tap meets 409.
  test('5: no Share trip button while searching or after the end', () {
    for (final status in [
      RideStatus.bookingRequested,
      RideStatus.findingDriver,
      RideStatus.searchDelayed,
      RideStatus.noDriverFound,
      RideStatus.tripCompleted,
      RideStatus.cancelledByRider,
    ]) {
      expect(
        WaitingShareButton.canShare(status, driverShown: true),
        isFalse,
        reason: '$status',
      );
    }
    for (final status in [
      RideStatus.driverAssigned,
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
      RideStatus.approachingDropoff,
    ]) {
      expect(
        WaitingShareButton.canShare(status, driverShown: true),
        isTrue,
        reason: '$status',
      );
    }
    expect(WaitingShareButton.canShare(null, driverShown: false), isTrue);
  });

  // 6: "ended" stuck for the whole session.
  test(
    '6: ended clears when a new live link exists or the trip changes',
    () async {
      await safety.load();
      await safety.shareLink('t1');
      server.links.clear();
      await safety.refreshShare('t1');
      expect(safety.shareEndedFor('t1'), isTrue);
      // A live link again (made on another phone): not ended any more.
      server.links.add(liveLink('sh_9'));
      await safety.refreshShare('t1');
      expect(safety.shareEndedFor('t1'), isFalse);
      // Ended again, then the rider is on another trip.
      await safety.shareLink('t1');
      server.links.clear();
      await safety.refreshShare('t1');
      expect(safety.shareEndedFor('t1'), isTrue);
      await safety.refreshShare('t2');
      expect(safety.shareEndedFor('t1'), isFalse);
    },
  );

  // 7: the trip-screen button hid only on the next parent rebuild.
  testWidgets('7: a 403 hides the trip screen button at once', (tester) async {
    await tester.runAsync(safety.load);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: WaitingShareButton(rideId: 't1')),
      ),
    );
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    server.zoneOff = true;
    await tester.runAsync(() async {
      try {
        await safety.shareLink('t1');
      } catch (_) {}
    });
    await tester.pump();
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
  });
}
