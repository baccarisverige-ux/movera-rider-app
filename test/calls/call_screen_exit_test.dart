import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';

import 'in_app_call_test.dart' show FakeApi, FakeEngine;

/// 2026-11-11 owner phone test (Android tablet, landscape): the call screen
/// had no way out and the third button was cut off at the right edge; the
/// rider and the driver could not hear each other. Fail-before: Speaker
/// off screen at 1280x800, no Close, a screen opened on an ended call
/// stayed, and an offer that came while the microphone was still being
/// taken was answered before the engine was open.
class _SlowEngine extends FakeEngine {
  final Completer<void> mic = Completer<void>();
  @override
  Future<void> open(List<Map<String, dynamic>> iceServers) async {
    await mic.future;
    await super.open(iceServers);
  }
}

TripCallSession _outgoing(FakeApi api, [FakeEngine? engine]) =>
    TripCallSession.outgoing(
      api: api,
      engine: engine ?? FakeEngine(),
      tripId: 't1',
      side: 'rider',
    );

Future<void> _host(WidgetTester tester, TripCallSession s, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => TripCallScreen.open(context, s, name: 'Anna'),
            child: const Text('trip'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('trip'));
  await tester.pumpAndSettle();
}

void _allOnScreen(WidgetTester tester, Size size, List<String> keys) {
  final screen = Offset.zero & size;
  for (final key in keys) {
    final rect = tester.getRect(find.byKey(ValueKey<String>(key)));
    expect(
      screen.contains(rect.topLeft) && screen.contains(rect.bottomRight),
      isTrue,
      reason: '$key at $rect is not fully on $size',
    );
  }
}

void main() {
  const sizes = [Size(390, 844), Size(1280, 800), Size(844, 390)];
  for (final size in sizes) {
    testWidgets('every call button and Close fit on $size', (tester) async {
      final s = _outgoing(FakeApi());
      await tester.runAsync(s.start);
      await _host(tester, s, size);
      expect(tester.takeException(), isNull);
      _allOnScreen(tester, size, [
        'call-close',
        'call-mute',
        'call-end',
        'call-speaker',
      ]);
      // Close leaves the screen (and hangs up the live call).
      await tester.tap(find.byKey(const ValueKey<String>('call-close')));
      await tester.pumpAndSettle();
      expect(find.byType(TripCallScreen), findsNothing);
      expect(s.over, isTrue);
    });
  }

  testWidgets('hang-up closes the screen at once', (tester) async {
    final api = FakeApi();
    final s = _outgoing(api);
    await tester.runAsync(s.start);
    await _host(tester, s, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey<String>('call-end')));
    await tester.pumpAndSettle();
    expect(find.byType(TripCallScreen), findsNothing);
    expect(api.sent, contains('end:cll_1:hangup'));
  });

  testWidgets('Android back leaves the call screen', (tester) async {
    final s = _outgoing(FakeApi());
    await tester.runAsync(s.start);
    await _host(tester, s, const Size(390, 844));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TripCallScreen), findsNothing);
  });

  testWidgets('a screen opened on a call already over closes by itself', (
    tester,
  ) async {
    final s = _outgoing(FakeApi());
    await tester.runAsync(s.start);
    await tester.runAsync(s.hangUp);
    await _host(tester, s, const Size(1280, 800));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(TripCallScreen), findsNothing);
  });

  test(
    'an offer that comes while the mic is being taken waits for it',
    () async {
      final engine = _SlowEngine();
      final api = FakeApi();
      final s = TripCallSession.incoming(
        api: api,
        engine: engine,
        call: const IncomingCall(callId: 'cll_1', tripId: 't1', from: 'driver'),
        side: 'rider',
        ice: const [],
      );
      final answering = s.answer();
      final offer = s.receive('call_signal', {
        'callId': 'cll_1',
        'from': 'driver',
        'type': 'offer',
        'sdp': 'v=0 driver-offer',
      });
      final ice = s.receive('call_signal', {
        'callId': 'cll_1',
        'from': 'driver',
        'type': 'ice',
        'candidate': {'candidate': 'c1', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });
      await Future<void>.delayed(Duration.zero);
      expect(engine.did, isEmpty);
      engine.mic.complete();
      await Future.wait([answering, offer, ice]);
      expect(engine.did, [
        'open',
        'acceptOffer:v=0 driver-offer',
        'candidate:c1',
      ]);
      expect(api.signals.single['type'], 'answer');
      expect(s.state, isNot(TripCallState.failed));
    },
  );
}
