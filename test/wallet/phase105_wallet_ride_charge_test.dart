import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _completed(
  String rideId, {
  String paymentMethod = 'Movera Wallet',
  double price = 259,
}) => RideSnapshot(
  status: RideStatus.tripCompleted,
  savedAt: DateTime.now(),
  pickupAddress: 'Pickup',
  destinationAddress: 'Destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: price,
  paymentMethod: paymentMethod,
  rideId: rideId,
);

class _CompletionRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);
  String? _rideId;
  int _sequence = 0;

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    _rideId = rideId;
    return _controller.stream;
  }

  void emit(RideStatus status) {
    _sequence += 1;
    _controller.add(
      RideRealtimeEvent(
        rideId: _rideId!,
        status: status,
        sequence: _sequence,
        at: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _controller.close();
}

Future<void> _pumpCompletion(
  WidgetTester tester, {
  required String rideId,
  required RideStatus status,
  required RideRealtime realtime,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(status: status, rideId: rideId, realtime: realtime),
      ),
    ),
  );
  await tester.pump();
}

Future<double> _balance(WidgetTester tester) async =>
    (await tester.runAsync(() => WalletStore().loadBalance()))!;

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

/// The completion screen of [snapshot] as Waiting leaves it: the snapshot
/// saved and remembered, the session on [session] for that ride.
Future<_CompletionRealtime> _openCompletion(
  WidgetTester tester,
  RideSnapshot snapshot, {
  RideStatus session = RideStatus.tripCompleted,
}) async {
  await tester.runAsync(() => RideSnapshotStore.save(snapshot));
  LastCompletedRide.remember(snapshot);
  AppScope.instance.ride
    ..rideId = snapshot.rideId
    ..status = session;
  final realtime = _CompletionRealtime();
  addTearDown(realtime.dispose);
  await _pumpCompletion(
    tester,
    rideId: snapshot.rideId!,
    status: snapshot.status,
    realtime: realtime,
  );
  await _settle(tester);
  return realtime;
}

Future<void> _tapDone(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ride-completed-done')));
  for (var i = 0; i < 4; i++) {
    await _settle(tester);
  }
}

final _submitError = find.byKey(const ValueKey('completion-submit-error'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 500.0});
    LastCompletedRide.clear();
  });

  testWidgets('a wallet-paid ride is deducted once payment is finalized',
      (tester) async {
    LastCompletedRide.remember(_completed('wr-1'));
    AppScope.instance.ride
      ..rideId = 'wr-1'
      ..status = RideStatus.tripCompleted;
    final realtime = _CompletionRealtime();
    addTearDown(realtime.dispose);

    await _pumpCompletion(
      tester,
      rideId: 'wr-1',
      status: RideStatus.tripCompleted,
      realtime: realtime,
    );
    await _settle(tester);
    expect(await _balance(tester), 500, reason: 'not charged before payment');

    realtime.emit(RideStatus.paymentFinalized);
    await _settle(tester);
    expect(await _balance(tester), 241);

    // Later completion states never charge the same ride again.
    realtime.emit(RideStatus.ratingPending);
    await _settle(tester);
    expect(await _balance(tester), 241);
  });

  testWidgets('opening completion already at paymentFinalized charges once',
      (tester) async {
    LastCompletedRide.remember(_completed('wr-2'));
    AppScope.instance.ride
      ..rideId = 'wr-2'
      ..status = RideStatus.paymentFinalized;
    final realtime = _CompletionRealtime();
    addTearDown(realtime.dispose);

    await _pumpCompletion(
      tester,
      rideId: 'wr-2',
      status: RideStatus.paymentFinalized,
      realtime: realtime,
    );
    await _settle(tester);
    expect(await _balance(tester), 241);

    // A second completion surface for the same ride (reload/restore).
    await tester.pumpWidget(const SizedBox());
    await _pumpCompletion(
      tester,
      rideId: 'wr-2',
      status: RideStatus.paymentFinalized,
      realtime: realtime,
    );
    await _settle(tester);
    expect(await _balance(tester), 241);
  });

  testWidgets('a card-paid ride leaves the wallet untouched', (tester) async {
    LastCompletedRide.remember(_completed('wr-3', paymentMethod: 'Apple Pay'));
    AppScope.instance.ride
      ..rideId = 'wr-3'
      ..status = RideStatus.paymentFinalized;
    final realtime = _CompletionRealtime();
    addTearDown(realtime.dispose);

    await _pumpCompletion(
      tester,
      rideId: 'wr-3',
      status: RideStatus.paymentFinalized,
      realtime: realtime,
    );
    await _settle(tester);
    expect(await _balance(tester), 500);
  });

  test('chargeCompletedRide ignores other rides and double charges', () async {
    final wallet = WalletController();
    expect(
      await wallet.chargeCompletedRide(_completed('a'), rideId: 'b'),
      isNull,
    );
    expect(await wallet.chargeCompletedRide(_completed('a'), rideId: 'a'), 241);
    expect(await wallet.chargeCompletedRide(_completed('a'), rideId: 'a'), isNull);
    expect(await WalletStore().loadBalance(), 241);
    expect(
      AppScope.instance.wallet.entries.where((e) => e.amountMinor == -25900),
      isNotEmpty,
    );
  });

  testWidgets('rider-72: Done still leaves when the session already holds a '
      'terminal payment status', (tester) async {
    // paymentFailed was reconciled while Waiting handed over to the summary.
    await _openCompletion(
      tester,
      _completed('pf-1', paymentMethod: 'Apple Pay'),
      session: RideStatus.paymentFailed,
    );
    await _tapDone(tester);
    expect(_submitError, findsNothing);
    expect(await tester.runAsync(RideSnapshotStore.readForArchive), isNull);
  });
}
