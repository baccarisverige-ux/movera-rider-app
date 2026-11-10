import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/sound/app_tones.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';

import '../calls/in_app_call_test.dart' show FakeApi, FakeEngine;

/// Rules REMINDERS rows 28–29 (contract v0.18.56 §78, §62): Movera's own
/// new-message sound for a driver message (admin `chat.sound`) and the
/// ring of an incoming in-app call until it is answered, declined or
/// missed. Riders have no read-aloud: `readAloudDefault` is the driver's.
class FakeTones implements TonePlayer {
  final List<String> log = [];
  @override
  Future<void> playOnce(String asset) async => log.add('once:$asset');
  @override
  Future<void> loop(String asset) async => log.add('loop:$asset');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> dispose() async => log.add('dispose');
}

Map<String, dynamic> msg(String id, String from) => {
  'messageId': id,
  'tripId': 'trp_1',
  'from': from,
  'text': 'Hi $id',
  'at': '2026-11-10T08:35:00Z',
};

void main() {
  late FakeTones tones;

  setUp(() {
    tones = FakeTones();
    AppTones.debugReset();
    AppTones.debugCreate = () => tones;
    MessagesController.debugResetSound();
  });

  tearDown(() {
    AppTones.debugCreate = null;
    AppTones.debugReset();
    MessagesController.debugResetSound();
    MessagesRepository.clearAllSessions();
  });

  test('a new driver message plays chat_message.wav once; a replay, the '
      'rider\'s own echo and an admin sound off stay quiet', () async {
    MessagesController.ingestStreamMessage('trp_1', msg('m1', 'driver'));
    MessagesController.ingestStreamMessage('trp_1', msg('m1', 'driver'));
    MessagesController.ingestStreamMessage('trp_1', msg('m2', 'rider'));
    await pumpEventQueue();
    expect(tones.log, ['once:${AppTones.chatMessage}']);

    MessagesController.debugSetSound('trp_1', false);
    MessagesController.ingestStreamMessage('trp_1', msg('m3', 'driver'));
    await pumpEventQueue();
    expect(tones.log, ['once:${AppTones.chatMessage}']);
  });

  test('ringtone loops while ringing and stops once', () {
    CallRingtone(player: tones)
      ..update(true)
      ..update(true)
      ..update(false)
      ..dispose();
    expect(tones.log, ['loop:${AppTones.callRing}', 'stop', 'dispose']);
  });

  TripCallSession incoming() => TripCallSession.incoming(
    api: FakeApi(),
    engine: FakeEngine(),
    call: const IncomingCall(callId: 'cll_1', tripId: 't1', from: 'driver'),
    side: 'rider',
    ice: const [],
  );

  Future<void> show(WidgetTester tester, TripCallSession s) =>
      tester.pumpWidget(MaterialApp(home: TripCallScreen(session: s)));

  testWidgets('the incoming call rings until Answer', (tester) async {
    final s = incoming();
    await show(tester, s);
    expect(tones.log, ['loop:${AppTones.callRing}']);
    await s.answer();
    await tester.pump();
    expect(tones.log, ['loop:${AppTones.callRing}', 'stop']);
    await tester.pumpWidget(const SizedBox());
    expect(tones.log.last, 'dispose');
  });

  testWidgets('Decline and a missed call stop the ring', (tester) async {
    final s = incoming();
    await show(tester, s);
    await s.decline();
    await tester.pump();
    expect(tones.log, ['loop:${AppTones.callRing}', 'stop']);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());

    tones.log.clear();
    final missed = incoming();
    await show(tester, missed);
    await missed.receive('call_missed', {'callId': 'cll_1'});
    await tester.pump();
    expect(tones.log, ['loop:${AppTones.callRing}', 'stop']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an outgoing call does not ring here', (tester) async {
    final s = TripCallSession.outgoing(
      api: FakeApi(),
      engine: FakeEngine(),
      tripId: 't1',
      side: 'rider',
    );
    await show(tester, s);
    expect(tones.log, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
