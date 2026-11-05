import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/data/rider_trip_calls.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';
import 'package:movera_rider/features/messages/presentation/trip_call.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.38 §62 (fix job 8, owner G15 2026-11-05: "In-app calls only",
/// "Both rider and driver", "Just 'Call failed'"): the rider calls the
/// driver inside the app and answers the driver's call. Fail-before: main
/// opens the dialer with a masked number or says "Calls coming soon".

class FakeEngine implements CallEngine {
  final List<String> did = [];
  List<Map<String, dynamic>>? ice;
  @override
  void Function(Map<String, dynamic> candidate)? onCandidate;
  @override
  void Function(CallMediaState state)? onMedia;
  @override
  Future<void> open(List<Map<String, dynamic>> iceServers) async {
    ice = iceServers;
    did.add('open');
  }

  @override
  Future<String> createOffer() async {
    did.add('offer');
    return 'v=0 rider-offer';
  }

  @override
  Future<String> acceptOffer(String sdp) async {
    did.add('acceptOffer:$sdp');
    return 'v=0 rider-answer';
  }

  @override
  Future<void> acceptAnswer(String sdp) async => did.add('acceptAnswer:$sdp');
  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async =>
      did.add('candidate:${candidate['candidate']}');
  @override
  Future<void> setMuted(bool muted) async => did.add('muted:$muted');
  @override
  Future<void> setSpeaker(bool on) async => did.add('speaker:$on');
  @override
  Future<void> close() async => did.add('close');
}

class FakeApi implements CallApi {
  final List<String> sent = [];
  final List<Map<String, dynamic>> signals = [];
  Object? startError;
  @override
  Future<Map<String, dynamic>> start(String tripId) async {
    sent.add('start:$tripId');
    if (startError != null) throw startError!;
    return {
      'tripId': tripId,
      'mode': 'in_app',
      'callId': 'cll_1',
      'ice': {
        'servers': [
          {
            'urls': ['stun:stun.example.test:3478'],
          },
        ],
        'ttlSeconds': 900,
      },
      'ringSeconds': 30,
      'maxCallMin': 15,
      'expiresAt': '2026-11-05T12:15:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> answer(String callId) async {
    sent.add('answer:$callId');
    return {
      'callId': callId,
      'state': 'answered',
      'ice': {'servers': [], 'ttlSeconds': 900},
    };
  }

  @override
  Future<void> end(String callId, String reason) async =>
      sent.add('end:$callId:$reason');
  @override
  Future<void> signal(String callId, Map<String, dynamic> body) async =>
      signals.add(body);
}

Map<String, dynamic> callOf(String from, String state) => {
  'callId': 'cll_1',
  'tripId': 't1',
  'from': from,
  'to': from == 'driver' ? 'rider' : 'driver',
  'state': state,
  'startedAt': '2026-11-05T12:00:00Z',
  'answeredAt': null,
  'endedAt': null,
  'endedReason': null,
  'seconds': 0,
};

Map<String, dynamic> callOf(String from, String state) => {
  'callId': 'cll_1',
  'tripId': 't1',
  'from': from,
  'to': from == 'driver' ? 'rider' : 'driver',
  'state': state,
  'startedAt': '2026-11-05T12:00:00Z',
  'answeredAt': null,
  'endedAt': null,
  'endedReason': null,
  'seconds': 0,
};

class InApp implements TripCallTransport {
  InApp(this.answer);
  final Object answer;
  @override
  Future<TripCall> call(String tripId) async {
    if (answer case final TripCall call) return call;
    throw answer;
  }
}

void main() {
  setUp(() => L10n.use('en'));

  test('the call event kinds are known and pass after the trip ended', () {
    for (final wire in [
      'call_ringing',
      'call_answered',
      'call_signal',
      'call_ended',
      'call_missed',
    ]) {
      final kind = RealtimeKindWire.parse(wire);
      expect(kind, isNotNull, reason: wire);
      expect(kind!.passesAfterTerminal, isTrue, reason: wire);
    }
  });

  test(
    'outgoing: the driver answers, offer → answer → connected; hang up',
    () async {
      final api = FakeApi();
      final engine = FakeEngine();
      final session = TripCallSession.outgoing(
        api: api,
        engine: engine,
        tripId: 't1',
        side: 'rider',
      );
      await session.start();
      expect(session.state, TripCallState.calling);
      await session.receive('call_answered', callOf('rider', 'answered'));
      expect(api.signals.first, {'type': 'offer', 'sdp': 'v=0 rider-offer'});
      await session.receive('call_signal', {
        'callId': 'cll_1',
        'from': 'driver',
        'type': 'answer',
        'sdp': 'v=0 driver-answer',
      });
      expect(engine.did, contains('acceptAnswer:v=0 driver-answer'));
      engine.onMedia!(CallMediaState.connected);
      expect(session.state, TripCallState.connected);
      await session.hangUp();
      expect(api.sent.last, 'end:cll_1:hangup');
    },
  );

  test('incoming from the driver: a ringing event for the rider opens a session; answer then the offer', () async {
    final api = FakeApi();
    final engine = FakeEngine();
    final hub = RiderTripCalls(api: api, engine: () => engine);
    TripCallSession? shown;
    hub.onIncoming = (s) => shown = s;
    hub.receive('t1', 'call_ringing', callOf('driver', 'ringing'));
    expect(shown, isNotNull);
    expect(shown!.state, TripCallState.ringing);
    await shown!.answer();
    hub.receive('t1', 'call_signal', {
      'callId': 'cll_1',
      'from': 'driver',
      'type': 'offer',
      'sdp': 'v=0 driver-offer',
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(engine.did, contains('acceptOffer:v=0 driver-offer'));
    // The rider's own ringing (to the driver) is not an incoming call.
    final other = RiderTripCalls(api: FakeApi(), engine: FakeEngine.new);
    other.receive('t1', 'call_ringing', callOf('rider', 'ringing'));
    expect(other.incoming.value, isNull);
  });

  test('a failure says only "Call failed" (sv, fr, en)', () async {
    final failing = TripCallSession.outgoing(
      api: FakeApi()..startError = StateError('x'),
      engine: FakeEngine(),
      tripId: 't1',
      side: 'rider',
    );
    await failing.start();
    expect(failing.state, TripCallState.failed);
    expect(L10n.current.callFailed, 'Call failed');
    L10n.use('sv');
    expect(L10n.current.callFailed, 'Samtalet misslyckades');
    L10n.use('fr');
    expect(L10n.current.callFailed, "L'appel a échoué");
  });

  Future<BuildContext> host(WidgetTester tester) async {
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
    return ctx;
  }

  testWidgets('an in-app answer opens the call screen, nothing dialled', (
    tester,
  ) async {
    final ctx = await host(tester);
    final dialled = <Uri>[];
    unawaited(
      callTripPeer(
        ctx,
        rideId: 't1',
        transport: InApp(
          const TripCall(
            tripId: 't1',
            mode: 'in_app',
            callId: 'cll_1',
            ice: [],
          ),
        ),
        calls: RiderTripCalls(api: FakeApi(), engine: FakeEngine.new),
        dial: (uri) async {
          dialled.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TripCallScreen), findsOneWidget);
    expect(find.text(L10n.current.callCalling), findsOneWidget);
    expect(dialled, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a refused call says only "Call failed"', (tester) async {
    final ctx = await host(tester);
    await callTripPeer(
      ctx,
      rideId: 't1',
      transport: InApp(StateError('409 call_window_closed')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Call failed'), findsOne);
    expect(find.byType(TripCallScreen), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
