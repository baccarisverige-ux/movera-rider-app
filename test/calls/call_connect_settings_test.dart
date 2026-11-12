import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'in_app_call_test.dart' show FakeApi, FakeEngine, callOf;

/// Contract v0.18.66 §87 (owner answers 2026-11-11, Rule 0 / Rule 16),
/// rider side (driver drv-87 bd30725f is the same):
/// (a) the connect time limit comes from the server with each call
/// (`TripCall.connectTimeoutSeconds` for the caller, `CallView` for the
/// callee: `call_ringing` and the answer), 25 s when missing, held to
/// 10–60; (b) when a call first connects the speaker is ON on a tablet
/// (shortest side ≥ 600 dp) and OFF on a phone, and the rider's own
/// Speaker choice is kept; (c) "Call failed" has the hint "Couldn't
/// connect. Check your network or use chat." under it only when the
/// connect time limit ran out (also the "Calling…" time-out).
/// Fail-before: the limit stays the fixed 25 s from rider #592, the
/// speaker is never set when the call connects, no hint is shown and no
/// hint text exists.
const _hint = "Couldn't connect. Check your network or use chat.";

/// The server's `TripCall` / answer `CallView` with its own connect time.
class _ApiWith extends FakeApi {
  _ApiWith({this.startSeconds, this.answerSeconds});
  final Object? startSeconds;
  final Object? answerSeconds;

  @override
  Future<Map<String, dynamic>> start(String tripId) async => {
    ...await super.start(tripId),
    if (startSeconds != null) 'connectTimeoutSeconds': startSeconds,
  };

  @override
  Future<Map<String, dynamic>> answer(String callId) async => {
    ...await super.answer(callId),
    if (answerSeconds != null) 'connectTimeoutSeconds': answerSeconds,
  };
}

Future<TripCallSession> _calledAndAnswered(FakeApi api) async {
  final session = TripCallSession.outgoing(
    api: api,
    engine: FakeEngine(),
    tripId: 't1',
    side: 'rider',
  );
  await session.start();
  await session.receive('call_answered', callOf('rider', 'answered'));
  expect(session.state, TripCallState.connecting);
  return session;
}

TripCallSession _incoming(FakeApi api, FakeEngine engine, {Object? seconds}) =>
    TripCallSession.incoming(
      api: api,
      engine: engine,
      call: IncomingCall.fromJson({
        ...callOf('driver', 'ringing'),
        if (seconds != null) 'connectTimeoutSeconds': seconds,
      }),
      side: 'rider',
      ice: const [],
    );

void _screen(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logical * 2;
  addTearDown(tester.view.reset);
}

Future<void> _openScreen(WidgetTester tester, TripCallSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => TripCallScreen.open(context, session),
            child: const Text('trip'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('trip'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => L10n.use('en'));

  group('(a) connect time limit from the server', () {
    testWidgets('caller: TripCall.connectTimeoutSeconds 12 → failed after '
        '12 s, not 25', (tester) async {
      final api = _ApiWith(startSeconds: 12);
      final session = await _calledAndAnswered(api);
      await tester.pump(const Duration(seconds: 11));
      expect(session.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 2));
      expect(session.state, TripCallState.failed);
      expect(api.sent.last, 'end:cll_1:failed');
    });

    testWidgets('caller: TripCall.connectTimeoutSeconds 40 → still '
        'connecting after 30 s, failed after 40', (tester) async {
      final session = await _calledAndAnswered(_ApiWith(startSeconds: 40));
      await tester.pump(const Duration(seconds: 30));
      expect(session.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 11));
      expect(session.state, TripCallState.failed);
    });

    testWidgets('caller: "Calling…" ends after ringSeconds + the server\'s '
        'connect time', (tester) async {
      final session = TripCallSession.outgoing(
        api: _ApiWith(startSeconds: 10),
        engine: FakeEngine(),
        tripId: 't1',
        side: 'rider',
      );
      await session.start();
      // ringSeconds 30 + 10.
      await tester.pump(const Duration(seconds: 39));
      expect(session.state, TripCallState.calling);
      await tester.pump(const Duration(seconds: 2));
      expect(session.state, TripCallState.failed);
    });

    testWidgets('callee: call_ringing CallView.connectTimeoutSeconds 40 → '
        'still connecting after 30 s, failed after 40', (tester) async {
      final api = FakeApi();
      final session = _incoming(api, FakeEngine(), seconds: 40);
      await session.answer();
      await tester.pump(const Duration(seconds: 30));
      expect(session.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 11));
      expect(session.state, TripCallState.failed);
      expect(api.sent.last, 'end:cll_1:failed');
    });

    testWidgets('callee: the answer\'s CallView.connectTimeoutSeconds 15 is '
        'used', (tester) async {
      final session = _incoming(_ApiWith(answerSeconds: 15), FakeEngine());
      await session.answer();
      await tester.pump(const Duration(seconds: 14));
      expect(session.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 2));
      expect(session.state, TripCallState.failed);
    });

    testWidgets('outside 10–60 is held to the range: 5 → 10 s, 300 → 60 s', (
      tester,
    ) async {
      final short = await _calledAndAnswered(_ApiWith(startSeconds: 5));
      await tester.pump(const Duration(seconds: 9));
      expect(short.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 2));
      expect(short.state, TripCallState.failed);

      final long = await _calledAndAnswered(_ApiWith(startSeconds: 300));
      await tester.pump(const Duration(seconds: 59));
      expect(long.state, TripCallState.connecting);
      await tester.pump(const Duration(seconds: 2));
      expect(long.state, TripCallState.failed);
    });

    testWidgets('missing or unreadable (older server) → 25 s', (tester) async {
      for (final value in <Object?>[null, 'x', 0]) {
        final session = await _calledAndAnswered(_ApiWith(startSeconds: value));
        await tester.pump(const Duration(seconds: 24));
        expect(session.state, TripCallState.connecting, reason: '$value');
        await tester.pump(const Duration(seconds: 2));
        expect(session.state, TripCallState.failed, reason: '$value');
      }
    });
  });

  group('(b) speaker default when the call connects', () {
    testWidgets('tablet (shortest side ≥ 600 dp): speaker ON', (tester) async {
      _screen(tester, const Size(800, 1280));
      final engine = FakeEngine();
      final session = _incoming(FakeApi(), engine);
      await session.answer();
      expect(engine.did, isNot(contains('speaker:true')));
      engine.onMedia!(CallMediaState.connected);
      await tester.pump();
      expect(session.speaker, isTrue);
      expect(engine.did, contains('speaker:true'));
      await session.hangUp();
    });

    testWidgets('phone (shortest side < 600 dp): speaker OFF (earpiece)', (
      tester,
    ) async {
      _screen(tester, const Size(390, 844));
      final engine = FakeEngine();
      final session = _incoming(FakeApi(), engine);
      await session.answer();
      engine.onMedia!(CallMediaState.connected);
      await tester.pump();
      expect(session.speaker, isFalse);
      expect(engine.did, contains('speaker:false'));
      await session.hangUp();
    });

    testWidgets('the Speaker button still switches it; a dropped and '
        'restored link keeps the rider\'s choice', (tester) async {
      _screen(tester, const Size(800, 1280));
      final engine = FakeEngine();
      final session = _incoming(FakeApi(), engine);
      await session.answer();
      engine.onMedia!(CallMediaState.connected);
      await tester.pump();
      await session.toggleSpeaker();
      expect(session.speaker, isFalse);
      engine.onMedia!(CallMediaState.disconnected);
      engine.onMedia!(CallMediaState.connected);
      await tester.pump();
      expect(session.speaker, isFalse);
      expect(engine.did.where((d) => d.startsWith('speaker:')), [
        'speaker:true',
        'speaker:false',
      ]);
      await session.hangUp();
    });

    testWidgets('the rider chose Speaker before the call connected: his '
        'choice is kept', (tester) async {
      _screen(tester, const Size(390, 844));
      final engine = FakeEngine();
      final session = _incoming(FakeApi(), engine);
      await session.answer();
      await session.toggleSpeaker();
      engine.onMedia!(CallMediaState.connected);
      await tester.pump();
      expect(session.speaker, isTrue);
      expect(engine.did.where((d) => d.startsWith('speaker:')), [
        'speaker:true',
      ]);
      await session.hangUp();
    });
  });

  group('(c) failure hint', () {
    testWidgets('connect time limit runs out → "Call failed" and the hint '
        'under it; the screen still closes 2 s later', (tester) async {
      final session = await _calledAndAnswered(_ApiWith(startSeconds: 12));
      await _openScreen(tester, session);
      expect(find.text(_hint), findsNothing);
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(find.text('Call failed'), findsOneWidget);
      expect(find.text(_hint), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Call failed'), findsNothing);
      expect(find.text('trip'), findsOneWidget);
    });

    testWidgets('"Calling…" runs out (no answer heard) → the hint too', (
      tester,
    ) async {
      final session = TripCallSession.outgoing(
        api: _ApiWith(startSeconds: 10),
        engine: FakeEngine(),
        tripId: 't1',
        side: 'rider',
      );
      await session.start();
      await _openScreen(tester, session);
      await tester.pump(const Duration(seconds: 40));
      await tester.pump();
      expect(find.text('Call failed'), findsOneWidget);
      expect(find.text(_hint), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('a call that fails another way (ICE failed) shows only '
        '"Call failed"', (tester) async {
      final engine = FakeEngine();
      final session = _incoming(FakeApi(), engine);
      await session.answer();
      await _openScreen(tester, session);
      engine.onMedia!(CallMediaState.failed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Call failed'), findsOneWidget);
      expect(find.text(_hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    test('the hint text is the contract\'s, in sv / fr / en', () {
      final contract =
          jsonDecode(File('contracts/contract.json').readAsStringSync())
              as Map<String, dynamic>;
      final texts =
          (contract['inAppCalls'] as Map)['texts'] as Map<String, dynamic>;
      final hint = texts['connectFailedHint'] as Map<String, dynamic>;
      for (final lang in ['sv', 'fr', 'en']) {
        L10n.use(lang);
        expect(L10n.current.callConnectFailedHint, hint[lang], reason: lang);
      }
    });
  });
}
