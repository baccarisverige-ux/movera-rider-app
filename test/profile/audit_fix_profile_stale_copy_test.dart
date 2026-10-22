// rider-r3-9 / rider-u154: Personal info and Privacy built each save from
// the profile they read at build time. The page rebuilds only once a save
// has reached the server, so a second edit made while the first was still
// on its way put the first one back.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/domain/rider_profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes the device copy at once and then waits on the network, as
/// SyncedProfileRepository does; [answer] lets the PATCHes land.
class _SlowServerProfile implements RiderProfileRepository {
  final _cache = ProfileRepository(storageKey: 'test_profile');
  final _waiting = <Completer<void>>[];

  int get inFlight => _waiting.length;

  void answer() {
    for (final call in _waiting) {
      call.complete();
    }
    _waiting.clear();
  }

  @override
  RiderProfileData get current => _cache.current;

  @override
  String displayName() => _cache.displayName();

  @override
  Future<void> hydrate() => _cache.hydrate();

  @override
  Future<void> hydrateLocal() => _cache.hydrate();

  @override
  void clearLocal() => _cache.clearLocal();

  @override
  Future<RiderProfileData> save(RiderProfileData next) async {
    await _cache.save(next);
    final call = Completer<void>();
    _waiting.add(call);
    await call.future;
    return _cache.current;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProfileController, _SlowServerProfile)> pump(
    WidgetTester tester,
    Widget Function(ProfileController) page,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _SlowServerProfile();
    final controller = ProfileController(store: store);
    await tester.pumpWidget(MaterialApp(home: page(controller)));
    await tester.pumpAndSettle();
    return (controller, store);
  }

  AccountSecurityController security() => AccountSecurityController(
    repository: AccountSecurityRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        client: InProcessMockClient(),
      ),
    ),
  );

  testWidgets(
    'rider-r3-9: a name saved during a gender save keeps the gender',
    (tester) async {
      final (profile, store) = await pump(
        tester,
        (c) => PersonalInfoPage(controller: c, securityController: security()),
      );

      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Woman'));
      await tester.pumpAndSettle();
      expect(store.inFlight, 1);

      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lina');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      store.answer();
      await tester.pumpAndSettle();

      expect(profile.profile.name, 'Lina');
      expect(profile.profile.gender, 'Woman');
      expect(find.text('Woman'), findsOneWidget);
    },
  );

  testWidgets('rider-u154: a second switch keeps the first one', (
    tester,
  ) async {
    final (profile, store) = await pump(
      tester,
      (c) => PrivacyPage(controller: c),
    );
    final before = profile.profile;
    Switch switchAt(int i) => tester.widget<Switch>(find.byType(Switch).at(i));
    final offers = switchAt(2).value;
    final email = switchAt(1).value;

    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    // The switch moves at once, before the server answers.
    expect(switchAt(2).value, !offers);
    expect(store.inFlight, 1);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    store.answer();
    await tester.pumpAndSettle();

    expect(profile.profile.promotions, !before.promotions);
    expect(profile.profile.emailUpdates, !email);
    expect(switchAt(2).value, !offers);
    expect(switchAt(1).value, !email);
  });
}
