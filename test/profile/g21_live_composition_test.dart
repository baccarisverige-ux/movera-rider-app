import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G21: the release composition must ask the server for the account, not
/// stop at once. With no server in the test the read fails, so the
/// controller reports the read failure (on main it never asked: available
/// stayed true with no state, and the card showed "unavailable" forever).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const production = AppEnv(
    flavor: AppFlavor.production,
    apiBaseUrl: 'https://api.movera.test',
  );

  testWidgets('production: the account read is attempted', (tester) async {
    final scope = AppScope.composeForEnvironment(production);
    addTearDown(scope.disposeForTest);
    final security = scope.accountSecurity;
    expect(security.built, isFalse);
    await tester.runAsync(security.load);
    expect(security.state, isNull);
    expect(security.available, isFalse);
    expect(security.errorMessage, isNotNull);
  });
}
