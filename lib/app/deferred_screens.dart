import 'package:flutter/widgets.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart'
    deferred as ride_history;
import 'package:movera_rider/features/messages/presentation/chat.dart'
    deferred as chat;
import 'package:movera_rider/features/wallet/presentation/wallet.dart'
    deferred as wallet;
import 'package:movera_rider/shared/widgets/deferred_screen.dart';

/// Owner 2026-11-03 (LT-4 "load on open"): Wallet, Ride history and Chat
/// are loaded the first time they open, so the app's first download is
/// smaller. Every place that opens them goes through here; nothing else in
/// lib/ may import those screens directly, or they would be back in the
/// first download (test/perf/deferred_screens_test.dart checks it).
Widget walletAndPaymentsScreen({int initialTab = 0}) => DeferredScreen(
  load: wallet.loadLibrary,
  builder: (_) => wallet.WalletAndPaymentsScreen(initialTab: initialTab),
);

Widget rideHistoryScreen() => DeferredScreen(
  load: ride_history.loadLibrary,
  builder: (_) => ride_history.RideHistory(),
);

Widget chatScreen({String? driverName, String? rideId}) => DeferredScreen(
  load: chat.loadLibrary,
  builder: (_) => chat.Chat(driverName: driverName, rideId: rideId),
);

/// Loads all three now (tests: a deferred load does not finish inside a
/// widget test's fake clock).
@visibleForTesting
Future<void> loadDeferredScreens() => Future.wait([
  wallet.loadLibrary(),
  ride_history.loadLibrary(),
  chat.loadLibrary(),
]);
