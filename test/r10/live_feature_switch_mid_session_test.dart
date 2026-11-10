// Owner 2026-11-10 "Yes, fix": wallet and booking ahead work at once when
// the admin switches them on mid-session. Before the fix di.dart chose the
// wallet and reservation repositories once at start-up from the switch of
// that moment, so a later `features.wallet` / `features.scheduledRides`
// from the server changed nothing until a restart. Behavioural, through
// the real composition root.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerFeatures.clear();
  });
  tearDown(ServerFeatures.clear);

  test('switched off at start-up, switched on mid-session: wallet and book '
      'later are available without a restart (and off again after)', () {
    ServerFeatures.apply({'wallet': false, 'scheduledRides': false});
    final scope = AppScope.composeForEnvironment(staging);
    addTearDown(scope.disposeForTest);
    final bookingLaterBuild = scope.flags.bookingLater;
    expect(scope.walletBalances.available, isFalse);
    if (!bookingLaterBuild) expect(scope.bookLaterAvailable, isFalse);

    // The admin switches both on; the next rider config carries it.
    ServerFeatures.apply({'wallet': true, 'scheduledRides': true});
    expect(scope.walletBalances.available, isTrue);
    expect(scope.walletBalances.inCurrency('EUR').available, isTrue);
    expect(scope.bookLaterAvailable, isTrue);

    ServerFeatures.apply({'wallet': false, 'scheduledRides': false});
    expect(scope.walletBalances.available, isFalse);
  });
}
