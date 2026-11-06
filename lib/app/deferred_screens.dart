import 'package:flutter/widgets.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart'
    deferred as personal_info;
import 'package:movera_rider/features/profile/presentation/privacy.dart'
    deferred as privacy;
import 'package:movera_rider/features/profile/presentation/security.dart'
    deferred as security;
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart'
    deferred as support;
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

/// B9 "Fast app start" (owner 2026-11-04): Help (support, its articles and
/// tickets) and the account settings pages (personal info, security,
/// privacy) load on first open too, the same way.
Widget supportHomeScreen() => DeferredScreen(
  load: support.loadLibrary,
  builder: (_) => support.SupportHome(),
);

Widget supportMessagesScreen() => DeferredScreen(
  load: support.loadLibrary,
  builder: (_) => support.SupportMessages(),
);

Widget selectIssueScreen({required SupportRide ride}) => DeferredScreen(
  load: support.loadLibrary,
  builder: (_) => support.SelectIssue(ride: ride),
);

Widget helpArticleScreen({required String title, required String body}) =>
    DeferredScreen(
      load: support.loadLibrary,
      builder: (_) => support.HelpArticle(title: title, body: body),
    );

Widget personalInfoScreen({
  ProfileController? controller,
  AccountSecurityController? securityController,
}) => DeferredScreen(
  load: personal_info.loadLibrary,
  builder: (_) => personal_info.PersonalInfoPage(
    controller: controller,
    securityController: securityController,
  ),
);

Widget securityScreen({AccountSecurityController? securityController}) =>
    DeferredScreen(
      load: security.loadLibrary,
      builder: (_) =>
          security.SecurityPage(securityController: securityController),
    );

Widget privacyScreen({ProfileController? controller}) => DeferredScreen(
  load: privacy.loadLibrary,
  builder: (_) => privacy.PrivacyPage(controller: controller),
);

/// Loads all of them now (tests: a deferred load does not finish inside a
/// widget test's fake clock).
@visibleForTesting
Future<void> loadDeferredScreens() => Future.wait([
  wallet.loadLibrary(),
  ride_history.loadLibrary(),
  chat.loadLibrary(),
  support.loadLibrary(),
  personal_info.loadLibrary(),
  security.loadLibrary(),
  privacy.loadLibrary(),
]);
