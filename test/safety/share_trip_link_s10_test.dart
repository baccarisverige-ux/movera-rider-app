// BQ-S10 "Share my trip" (contract v0.18.116 contract.json#shareTrip; owner
// 2026-11-02 Q1 "Build it for real", S10 answers Q1-Q7, Q-A, Q-B, 3b, 3c:
// Rules decisions/driver-g14.md). Before: the contract wire answered every
// share with "not on server", the contact's "Share trips" stayed on the
// phone, and nothing hid Share trip when the zone's switch was off.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/share_trip_actions.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
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
  Map<String, dynamic> contacts = {'items': <Object>[], 'updatedAt': null};
  final links = <Map<String, dynamic>>[];
  bool zoneOff = false;
  bool deleteFails = false;

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
        return json({...link, 'url': _url}, 201);
      }
      if (request.method == 'DELETE') {
        if (deleteFails) {
          return json({'code': 'unavailable', 'message': 'no'}, 503);
        }
        links.clear();
        return http.Response('', 204);
      }
      return json({'items': links});
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

  test('contact flag round-trip: Share trips goes to the server and comes '
      'back', () async {
    await addAnna();
    expect(server.contacts['items'], [
      {
        'name': 'Anna',
        'phone': '+46701740661',
        'relation': 'Other',
        'shareTrips': true,
      },
    ]);
    await safety.editContact(
      safety.contacts.single.copyWith(shareTrips: false),
    );
    expect((server.contacts['items'] as List).single['shareTrips'], false);
    // Another phone of the same rider reads the server's value.
    server.contacts = {
      'items': [
        {'name': 'Anna', 'phone': '+46701740661', 'shareTrips': true},
        {'name': 'Bo', 'phone': '+46701740662'},
      ],
      'updatedAt': '2026-11-16T09:00:00Z',
    };
    final read = ContractContactsRemoteDataSource.merge(
      server.contacts['items'],
      [safety.contacts.single],
    );
    expect(read.map((c) => c.shareTrips), [true, false]);
  });

  test('the zone switch: shareTrip.on false hides the feature', () {
    final off = RiderAppConfig.fromJson({
      'version': 3,
      'currency': 'SEK',
      'zoneId': 'Z001',
      'shareTrip': {'on': false},
      'features': {'shareTrip': true, 'wallet': true},
    })!;
    expect(off.features['shareTrip'], isFalse);
    expect(off.features['wallet'], isTrue);
    ServerFeatures.apply(off.features);
    expect(safety.shareTripOn, isFalse);
    ServerFeatures.apply({'shareTrip': true});
    expect(safety.shareTripOn, isTrue);
  });

  testWidgets('hidden when off: no Share trip button and no sheet', (
    tester,
  ) async {
    ServerFeatures.apply({'shareTrip': false});
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const WaitingShareButton(rideId: 't1');
            },
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    await showShareTripSheet(context, rideId: 't1');
    await tester.pump();
    expect(find.byType(ShareTripSheet), findsNothing);
    ServerFeatures.apply({'shareTrip': true});
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: WaitingShareButton(rideId: 't1')),
      ),
    );
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
  });

  testWidgets('Send opens the SMS app for the contact with the link; the '
      'link is made once', (tester) async {
    await tester.runAsync(addAnna);
    await pumpSheet(tester);
    expect(find.text('Anna'), findsOneWidget);
    expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
    await tap(tester, find.byKey(const ValueKey('share-trip-send-0')));
    expect(sms, hasLength(1));
    expect(sms.single.scheme, 'sms');
    expect(sms.single.path, '+46701740661');
    final body = Uri.decodeComponent(
      sms.single.query.substring('body='.length),
    );
    expect(body, 'Follow my Movera ride live: $_url');
    await tap(tester, find.byKey(const ValueKey('share-trip-send-0')));
    expect(sms, hasLength(2));
    expect(server.calls.where((c) => c == 'POST $_sharePath'), hasLength(1));
  });

  testWidgets('Share with… hands the message to the system share sheet', (
    tester,
  ) async {
    await tester.runAsync(safety.load);
    await pumpSheet(tester);
    await tap(tester, find.byKey(const ValueKey('share-trip-with')));
    expect(shared, ['Follow my Movera ride live: $_url']);
  });

  testWidgets('Stop sharing calls DELETE and the kept link is gone', (
    tester,
  ) async {
    await tester.runAsync(safety.load);
    await pumpSheet(tester);
    expect(find.byKey(const ValueKey('share-trip-stop')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('share-trip-with')));
    await tap(tester, find.byKey(const ValueKey('share-trip-stop')));
    expect(server.calls, contains('DELETE $_sharePath'));
    expect(server.links, isEmpty);
    expect(find.byKey(const ValueKey('share-trip-stop')), findsNothing);
    // The next share makes a new link: the old URL was not kept.
    await tap(tester, find.byKey(const ValueKey('share-trip-with')));
    expect(server.calls.where((c) => c == 'POST $_sharePath'), hasLength(2));
  });

  testWidgets('403 share_trip_off: the sheet says sharing is not available '
      'here and opens nothing', (tester) async {
    server.zoneOff = true;
    await tester.runAsync(safety.load);
    await pumpSheet(tester);
    await tap(tester, find.byKey(const ValueKey('share-trip-with')));
    expect(shared, isEmpty);
    expect(find.text('Trip sharing is not available here.'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-trip-with')), findsNothing);
  });

  test('auto-share asks to open the sheet once per ride, only in auto mode, '
      'and makes no link by itself', () async {
    await addAnna();
    await safety.setTripShare(enabled: true, mode: TripShareMode.manual);
    expect(await safety.autoShareRide('t1'), isFalse);
    await safety.setTripShare(enabled: true, mode: TripShareMode.auto);
    expect(safety.preferences.tripShareMode, TripShareMode.auto);
    expect(await safety.autoShareRide('t2'), isTrue);
    expect(await safety.autoShareRide('t2'), isFalse);
    ServerFeatures.apply({'shareTrip': false});
    expect(await safety.autoShareRide('t3'), isFalse);
    expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  // Round 2, supervisor MF-R1: the link is on the phone only while sharing
  // is live. Before, nothing dropped it when the trip ended.
  test('MF-R1: the trip ending drops the kept link, with no request', () async {
    await safety.load();
    expect(await safety.shareLink('t1'), _url);
    expect((await local.load()).shares['t1']?.url, _url);
    server.calls.clear();
    await SafetyController.dropShareForRideEnd('t1');
    expect(safety.shareFor('t1'), isNull);
    expect((await local.load()).shares.containsKey('t1'), isFalse);
    expect(server.calls, isEmpty);
    // The ride-end hook of the ride controller (completion and every
    // cancel) drops it too, even when the link was not live any more.
    expect(await safety.shareLink('t1'), _url);
    server.links.clear();
    await safety.refreshShare('t1');
    await SafetyController.stopShareForRideEnd('t1');
    expect((await local.load()).shares.containsKey('t1'), isFalse);
  });

  test('MF-R1: the ride-end hook drops the link even when the stop request '
      'fails', () async {
    await safety.load();
    expect(await safety.shareLink('t1'), _url);
    server.deleteFails = true;
    await SafetyController.stopShareForRideEnd('t1');
    expect(server.calls, contains('DELETE $_sharePath'));
    expect(safety.shareFor('t1')?.url, isNull);
    expect((await local.load()).shares['t1']?.url, isNull);
  });

  test('MF-R1: on load a kept share past its end is dropped', () async {
    final now = DateTime.now().toUtc();
    TripShare kept(String id, DateTime end) => TripShare(
      shareId: 'sh_$id',
      rideId: id,
      userId: '',
      expiresAt: end,
      url: _url,
      isActive: true,
    );
    await local.load();
    await local.save(
      SafetyCache(
        shares: {
          'old': kept('old', now.subtract(const Duration(minutes: 1))),
          'live': kept('live', now.add(const Duration(hours: 1))),
        },
      ),
    );
    final next = controllerOn(local);
    await next.load();
    expect(next.shareFor('old'), isNull);
    expect(next.shareFor('live')?.url, _url);
    expect((await local.load()).shares.keys, ['live']);
  });

  // Round 2, supervisor SF-R1: a link stopped from another phone must not
  // be sent again because some other link of the trip is live.
  test('SF-R1: the kept URL stays only while the server lists the same '
      'shareId', () async {
    await safety.load();
    expect(await safety.shareLink('t1'), _url);
    await safety.refreshShare('t1');
    expect(safety.shareFor('t1')?.canSend, isTrue, reason: 'same shareId');
    // Another phone stopped sharing and made a new link.
    server.links
      ..clear()
      ..add({
        'shareId': 'sh_other',
        'tripId': 't1',
        'createdAt': '2026-11-16T08:05:00Z',
        'expiresAt': '2099-01-01T00:00:00Z',
        'endsAtDropoff': true,
      });
    await safety.refreshShare('t1');
    final now = safety.shareFor('t1');
    expect(now?.isActive, isTrue);
    expect(now?.url, isNull, reason: 'the dead link is not kept');
    expect(now?.canSend, isFalse);
    final posts = server.calls.where((c) => c == 'POST $_sharePath').length;
    await safety.shareLink('t1');
    expect(
      server.calls.where((c) => c == 'POST $_sharePath'),
      hasLength(posts + 1),
    );
  });

  // Round 2, supervisor SF-R2: a held booked ride (accepted, the driver not
  // shown to the rider yet) cannot be shared: the server answers 409.
  testWidgets('SF-R2: no share button for a held booked ride until the '
      'driver is on the way', (tester) async {
    Future<void> pump(RideStatus status, bool driverShown) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WaitingShareButton(
            rideId: 't1',
            status: status,
            driverShown: driverShown,
          ),
        ),
      ),
    );
    await pump(RideStatus.driverAssigned, false);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    await pump(RideStatus.driverAssigned, true);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    await pump(RideStatus.driverArriving, false);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    await pump(RideStatus.tripInProgress, false);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
  });

  test('the texts promise no car position before pickup or near stops', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      for (final text in [l.shareTripWhatTheySee, l.shareLinkNote]) {
        expect(text, isNot(contains('{')), reason: '$locale');
        expect(text.length, greaterThan(40), reason: '$locale');
      }
      expect(l.shareTripMessage(_url), contains(_url), reason: '$locale');
    }
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.shareTripWhatTheySee, contains('only while you are in the car'));
    expect(en.shareTripWhatTheySee, contains('pickup'));
    expect(en.shareTripWhatTheySee, contains('stop'));
    expect(en.shareTripWhatTheySee, contains('drop-off'));
  });
}
