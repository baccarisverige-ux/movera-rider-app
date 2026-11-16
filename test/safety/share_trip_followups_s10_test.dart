// BQ-S10 follow-ups (supervisor round 2 / 2b, audits/impact/s10-share-trip-
// supervisor.md):
// - SF-R4: a share link kept on the phone must not outlive its trip when the
//   app was not there at the end (closed, or a booked ride's live page not
//   open). On start and on resume the app asks the server's existing list
//   (GET /rider/trips/{tripId}/share) for every kept link and drops the link
//   when the server no longer lists it (the trip ended, the link was stopped,
//   the zone is off, the trip is gone). No new server route.
// - SF-R5: the Safety sheet's "Share trip" tool is gated like the trip
//   screen's share button (no tool for a held booked ride, whose driver the
//   rider is not shown yet: the server answers 409 trip_not_live).
// - SF-R6: the shareIds the server listed are kept per trip.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/lifecycle/app_lifecycle.dart';
import 'package:movera_rider/app/signed_in_loads.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.example.test',
);
const _url = 'https://share.example.test/s/AbCdEfGhIjKlMnOpQrStUv';

String _path(String tripId) => '/api/v1/rider/trips/$tripId/share';

/// The server's share list per trip. A trip missing from [lists] answers
/// 404; one in [failing] answers 503.
class _Server {
  final calls = <String>[];
  final lists = <String, List<Map<String, dynamic>>>{};
  final failing = <String>{};

  Future<http.Response> answer(http.Request request) async {
    calls.add('${request.method} ${request.url.path}');
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path.endsWith('/emergency-contacts')) {
      return json({'items': <Object>[], 'updatedAt': null});
    }
    final match = RegExp(
      r'^/api/v1/rider/trips/([^/]+)/share$',
    ).firstMatch(request.url.path);
    if (match != null && request.method == 'GET') {
      final trip = match.group(1)!;
      if (failing.contains(trip)) {
        return json({'code': 'unavailable', 'message': 'no'}, 503);
      }
      final items = lists[trip];
      if (items == null) {
        return json({
          'code': 'not_found',
          'reason': 'trip_not_found',
          'message': 'no',
          'requestId': 'r',
        }, 404);
      }
      return json({'items': items});
    }
    return json({'code': 'not_found', 'message': 'no'}, 404);
  }
}

Map<String, dynamic> _item(String trip, String shareId) => {
  'shareId': shareId,
  'tripId': trip,
  'createdAt': '2026-11-16T08:00:00Z',
  'expiresAt': '2099-01-01T00:00:00Z',
  'endsAtDropoff': true,
};

TripShare _kept(String trip, {String? shareId}) => TripShare(
  shareId: shareId ?? 'sh_$trip',
  rideId: trip,
  userId: '',
  startedAt: DateTime.utc(2026, 11, 16, 8),
  // Not past its 6 h end: the load rule (round 2) does not drop it.
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 5)),
  url: '$_url$trip',
  isActive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _Server server;
  late PreferencesSafetyLocalDataSource local;

  /// A controller on [local], like the app after a restart.
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

  Future<void> keep(Map<String, TripShare> shares) async {
    await local.load();
    await local.save(SafetyCache(shares: shares));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerFeatures.clear();
    server = _Server();
    local = PreferencesSafetyLocalDataSource(memoryOnly: true);
  });

  tearDown(() {
    SafetyController.sharedForTest = null;
    ServerFeatures.clear();
  });

  group('SF-R4: a kept link leaves the phone when its trip is over', () {
    test('the server lists no live link (the trip ended while the app was '
        'closed): dropped from memory and disk', () async {
      await keep({'ended': _kept('ended')});
      server.lists['ended'] = [];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(server.calls, contains('GET ${_path('ended')}'));
      expect(safety.shareFor('ended'), isNull);
      expect((await local.load()).shares.containsKey('ended'), isFalse);
    });

    test('the server lists THAT link: the link stays', () async {
      await keep({'live': _kept('live')});
      server.lists['live'] = [_item('live', 'sh_live')];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(safety.shareFor('live')?.url, '${_url}live');
      expect((await local.load()).shares['live']?.url, '${_url}live');
    });

    test('the server lists another link only (stopped on another phone): '
        'the kept URL leaves', () async {
      await keep({'other': _kept('other')});
      server.lists['other'] = [_item('other', 'sh_new')];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(safety.shareFor('other')?.url, isNull);
      expect((await local.load()).shares['other']?.url, isNull);
    });

    test('the trip is gone (404): dropped', () async {
      await keep({'gone': _kept('gone')});
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(server.calls, contains('GET ${_path('gone')}'));
      expect(safety.shareFor('gone'), isNull);
      expect((await local.load()).shares.containsKey('gone'), isFalse);
    });

    test('no answer (503 / offline): kept, the 6 h rule still holds', () async {
      await keep({'busy': _kept('busy')});
      server.failing.add('busy');
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(safety.shareFor('busy')?.url, '${_url}busy');
    });

    test('several trips: each is asked once; only the ended ones go', () async {
      await keep({'a': _kept('a'), 'b': _kept('b'), 'c': _kept('c').ended()});
      server.lists['a'] = [];
      server.lists['b'] = [_item('b', 'sh_b')];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(safety.shareFor('a'), isNull);
      expect(safety.shareFor('b')?.url, '${_url}b');
      // A share with no link holds nothing to leak: no request for it.
      expect(
        server.calls.where((c) => c.startsWith('GET /api/v1/rider/trips')),
        ['GET ${_path('a')}', 'GET ${_path('b')}'],
      );
    });

    test('nothing kept: no request at all (no extra load on resume)', () async {
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await SafetyController.sweepKeptShares();
      expect(server.calls, isEmpty);
    });

    test('start: the signed-in start reads run the sweep', () async {
      await keep({'ended': _kept('ended')});
      server.lists['ended'] = [];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      await startServerReads();
      for (var i = 0; i < 50; i++) {
        if (!(await local.load()).shares.containsKey('ended')) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.calls, contains('GET ${_path('ended')}'));
      expect((await local.load()).shares.containsKey('ended'), isFalse);
    });

    test('resume: the app lifecycle runs the sweep', () async {
      await keep({'ended': _kept('ended')});
      server.lists['ended'] = [];
      final safety = controllerOn(local);
      SafetyController.sharedForTest = safety;
      AppLifecycleObserver().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      for (var i = 0; i < 50; i++) {
        if (!(await local.load()).shares.containsKey('ended')) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.calls, contains('GET ${_path('ended')}'));
      expect(safety.shareFor('ended'), isNull);
      expect((await local.load()).shares.containsKey('ended'), isFalse);
    });
  });

  // SF-R6: the listed shareIds are kept per trip.
  test('SF-R6: a read of another trip does not change a trip\'s listed '
      'links', () async {
    server.lists['a'] = [_item('a', 'sh_a')];
    server.lists['b'] = [_item('b', 'sh_b1'), _item('b', 'sh_b2')];
    final remote = ContractContactsRemoteDataSource(
      ApiClient(client: MockClient(server.answer), env: _staging),
    );
    await remote.getShare('a');
    await remote.getShare('b');
    expect(remote.liveShareIdsFor('a'), {'sh_a'});
    expect(remote.liveShareIdsFor('b'), {'sh_b1', 'sh_b2'});
    expect(remote.liveShareIdsFor('c'), isEmpty);
    server.lists['a'] = [];
    await remote.getShare('a');
    expect(remote.liveShareIdsFor('a'), isEmpty);
    expect(remote.liveShareIdsFor('b'), {'sh_b1', 'sh_b2'});
  });

  group(
    'SF-R5: the Safety sheet\'s Share trip tool is gated like the button',
    () {
      Future<void> openKit(
        WidgetTester tester, {
        required bool shareAllowed,
      }) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final safety = controllerOn(local);
        SafetyController.sharedForTest = safety;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Center(
                child: SafetyKitMapButton(
                  rideId: 't1',
                  shareAllowed: shareAllowed,
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('trip-safety-button')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('safety-sos')),
          findsOneWidget,
          reason: 'the sheet is open, during a trip',
        );
      }

      testWidgets('a held booked ride (no driver shown): no Share trip tool', (
        tester,
      ) async {
        await openKit(tester, shareAllowed: false);
        expect(find.byIcon(Icons.ios_share_outlined), findsNothing);
        expect(find.text('Share trip'), findsNothing);
      });

      testWidgets('a driver shown: the Share trip tool is there', (
        tester,
      ) async {
        await openKit(tester, shareAllowed: true);
        expect(find.byIcon(Icons.ios_share_outlined), findsOneWidget);
      });
    },
  );
}
