import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/calls/application/rider_trip_calls.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'in_app_call_test.dart' show FakeApi, FakeEngine, callOf;

/// 2026-11-11 owner phone test ("keep write connecting and never start"):
/// a call stayed on "Connecting…" for ever. Nothing ended it when the
/// other phone was never reached (no TURN on staging, only STUN) or when
/// the offer / answer / ICE never came, and ICE "disconnected" and the ICE
/// state itself were not heard. Fail-before: after Answer with no offer,
/// after the offer with no answer, after the link dropped, and with the
/// caller's "call answered" lost, the state stays connecting / calling;
/// the engine reports nothing for ICE failed / disconnected.
const _wait = Duration(seconds: 25);

Future<TripCallSession> _answered(FakeApi api, FakeEngine engine) async {
  final hub = RiderTripCalls(api: api, engine: () => engine);
  TripCallSession? shown;
  hub.onIncoming = (s) => shown = s;
  hub.receive('t1', 'call_ringing', callOf('driver', 'ringing'));
  await shown!.answer();
  return shown!;
}

class _SlowMic extends FakeEngine {
  final Completer<void> mic = Completer<void>();
  @override
  Future<void> open(List<Map<String, dynamic>> iceServers) async {
    await mic.future;
    await super.open(iceServers);
  }
}

void main() {
  setUp(() => L10n.use('en'));

  testWidgets('callee: Answer, then no offer → "Call failed" after the '
      'connect time, the server hears failed, the mic is let go', (
    tester,
  ) async {
    final api = FakeApi();
    final engine = FakeEngine();
    final session = await _answered(api, engine);
    expect(session.state, TripCallState.connecting);
    await tester.pump(_wait - const Duration(seconds: 1));
    expect(session.state, TripCallState.connecting);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state, TripCallState.failed);
    expect(api.sent.last, 'end:cll_1:failed');
    expect(engine.did.last, 'close');
  });

  testWidgets('the microphone question is not counted: the connect time '
      'starts once the mic is ours', (tester) async {
    final api = FakeApi();
    final engine = _SlowMic();
    final session = TripCallSession.incoming(
      api: api,
      engine: engine,
      call: IncomingCall.fromJson(callOf('driver', 'ringing')),
      side: 'rider',
      ice: const [],
    );
    final answering = session.answer();
    await tester.pump(const Duration(minutes: 1));
    expect(session.state, TripCallState.connecting);
    engine.mic.complete();
    await answering;
    await tester.pump(_wait - const Duration(seconds: 1));
    expect(session.state, TripCallState.connecting);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state, TripCallState.failed);
  });

  testWidgets('caller: offer sent, no answer / ICE never connects → failed', (
    tester,
  ) async {
    final api = FakeApi();
    final engine = FakeEngine();
    final session = TripCallSession.outgoing(
      api: api,
      engine: engine,
      tripId: 't1',
      side: 'rider',
    );
    await session.start();
    await session.receive('call_answered', callOf('rider', 'answered'));
    expect(api.signals.first['type'], 'offer');
    expect(session.state, TripCallState.connecting);
    await tester.pump(_wait + const Duration(seconds: 1));
    expect(session.state, TripCallState.failed);
    expect(api.sent.last, 'end:cll_1:failed');
  });

  testWidgets('connected in time: the timer is gone, the call goes on', (
    tester,
  ) async {
    final api = FakeApi();
    final engine = FakeEngine();
    final session = await _answered(api, engine);
    await tester.pump(const Duration(seconds: 5));
    engine.onMedia!(CallMediaState.connected);
    await tester.pump(const Duration(minutes: 2));
    expect(session.state, TripCallState.connected);
    expect(api.sent.where((s) => s.startsWith('end:')), isEmpty);
    await session.hangUp();
  });

  testWidgets('ICE disconnected: "Connecting…" again; back in time → the '
      'call goes on; not back → failed', (tester) async {
    final api = FakeApi();
    final engine = FakeEngine();
    final session = await _answered(api, engine);
    engine.onMedia!(CallMediaState.connected);
    engine.onMedia!(CallMediaState.disconnected);
    expect(session.state, TripCallState.connecting);
    await tester.pump(const Duration(seconds: 10));
    engine.onMedia!(CallMediaState.connected);
    expect(session.state, TripCallState.connected);
    await tester.pump(_wait * 2);
    expect(session.state, TripCallState.connected);
    engine.onMedia!(CallMediaState.disconnected);
    await tester.pump(_wait + const Duration(seconds: 1));
    expect(session.state, TripCallState.failed);
    expect(api.sent.last, 'end:cll_1:failed');
  });

  testWidgets('ICE failed ends the call at once', (tester) async {
    final api = FakeApi();
    final engine = FakeEngine();
    final session = await _answered(api, engine);
    engine.onMedia!(CallMediaState.failed);
    await tester.pump();
    expect(session.state, TripCallState.failed);
    expect(api.sent.last, 'end:cll_1:failed');
  });

  testWidgets('caller: "call answered" never reaches this phone → "Calling…" '
      'ends as failed after the ring time plus the connect time', (
    tester,
  ) async {
    final api = FakeApi();
    final session = TripCallSession.outgoing(
      api: api,
      engine: FakeEngine(),
      tripId: 't1',
      side: 'rider',
    );
    await session.start();
    // FakeApi.start: ringSeconds 30.
    await tester.pump(const Duration(seconds: 30) + _wait ~/ 2);
    expect(session.state, TripCallState.calling);
    await tester.pump(_wait);
    expect(session.state, TripCallState.failed);
    expect(api.sent.last, 'end:cll_1:failed');
  });

  testWidgets('the call screen says "Call failed" once the connect time is '
      'over', (tester) async {
    final session = await _answered(FakeApi(), FakeEngine());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  TripCallScreen.open(context, session, name: 'Anna'),
              child: const Text('trip'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connecting…'), findsOneWidget);
    await tester.pump(_wait);
    await tester.pump();
    expect(find.text('Connecting…'), findsNothing);
    expect(find.text('Call failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
