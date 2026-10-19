import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/ride_complete_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/features/ride_complete/presentation/driver_info.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/features/saved_places/presentation/confirm_location.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  ReservationController emptyReservations() {
    return ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
  }

  SafetyController emptySafety() {
    return SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      ),
    );
  }

  ProfileController emptyProfile() {
    return ProfileController(
      store: ProfileRepository(storageKey: 'phase4_privacy'),
    );
  }

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Size viewport = const Size(390, 844),
    bool settle = true,
  }) async {
    await setViewport(tester, viewport);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(home: screen),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void expectNoFakeProductionData() {
    expect(find.textContaining('Skypulse'), findsNothing);
    expect(find.textContaining('I11/Street'), findsNothing);
    expect(find.textContaining('Marle'), findsNothing);
    expect(find.textContaining('RID2ESSA'), findsNothing);
    expect(find.textContaining(r'$10.12'), findsNothing);
  }

  Future<void> expectCopy(
    WidgetTester tester,
    String text, {
    required String reason,
    bool containing = false,
  }) async {
    Finder onstage() =>
        containing ? find.textContaining(text) : find.text(text);
    if (onstage().evaluate().isEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(onstage(), 240);
      await tester.pump();
    }
    expect(onstage(), findsWidgets, reason: reason);
  }

  testWidgets('notifications empty state is designed and has no fake events', (
    tester,
  ) async {
    await pumpScreen(tester, const NotificationScreen());
    expect(find.byType(MoveraEmptyState), findsOneWidget);
    expect(find.text("You're all caught up."), findsOneWidget);
    expect(find.text('Driver assigned'), findsNothing);
    expect(find.textContaining(r'$10.00'), findsNothing);
    expect(find.textContaining('Marle'), findsNothing);
  });

  testWidgets('history loading does not show empty at the same time', (
    tester,
  ) async {
    final delayed = Completer<List<Reservation>>();
    await pumpScreen(
      tester,
      RideHistory(
        reservations: emptyReservations(),
        onDemandReader: () => delayed.future,
      ),
      settle: false,
    );
    await tester.tap(find.text('Completed'));
    await tester.pump();

    expect(find.text('Loading rides'), findsOneWidget);
    expect(find.text('No completed rides yet'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    delayed.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('Loading rides'), findsNothing);
    expect(find.text('No completed rides yet'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
  });

  testWidgets('history error offers a real retry without raw exceptions', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(
      tester,
      RideHistory(
        reservations: emptyReservations(),
        onDemandReader: () async {
          calls += 1;
          if (calls == 1) {
            throw StateError('disk-corrupt-xyz');
          }
          return const [];
        },
      ),
    );
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load rides'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('disk-corrupt-xyz'), findsNothing);
    expect(find.text('No completed rides yet'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Couldn’t load rides'), findsNothing);
    expect(find.text('No completed rides yet'), findsOneWidget);
  });

  testWidgets('history Book a ride returns to the previous screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RideHistory(
                          reservations: emptyReservations(),
                          onDemandReader: () async => const [],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open history'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book a ride'));
    await tester.pumpAndSettle();

    expect(find.text('Open history'), findsOneWidget);
    expect(find.text('No completed rides yet'), findsNothing);
  });

  testWidgets('driver chat shows an honest empty conversation', (tester) async {
    await pumpScreen(tester, const Chat());
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text("Driver’s name"), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(
      find.textContaining('when the ride is connected'),
      findsOneWidget,
    );
  });

  testWidgets('waiting driver card is designed when no driver is matched', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: WaitingDriverCard(
          driver: null,
          onOpenProfile: () {},
          onCall: () {},
          onMore: () {},
        ),
      ),
    );
    expect(find.byType(MoveraEmptyState), findsOneWidget);
    expect(find.text('Driver details unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.person_search_outlined), findsOneWidget);
    expect(find.textContaining('Merle'), findsNothing);
  });

  testWidgets('tip and receipt empties stay designed with no fake values', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              RideCompletedAddTip(
                controller: RideCompleteController(
                  tips: TipCatalog(amounts: []),
                ),
              ),
              RideCompletedTripDetail(),
              RideCompletedDriverInfo(),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Tips unavailable'), findsOneWidget);
    expect(find.text('Trip details unavailable'), findsOneWidget);
    expect(find.text('Driver details unavailable'), findsOneWidget);
    expect(find.text(r'$1'), findsNothing);
    expectNoFakeProductionData();
  });

  testWidgets('empty Home and Work shortcuts open the save-location flow', (
    tester,
  ) async {
    await pumpScreen(tester, const RiderSearchPickupLocation());
    expect(find.text('Not saved yet'), findsNWidgets(2));

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Add new address'), findsOneWidget);
    expect(find.text('Add location'), findsOneWidget);

    Navigator.of(tester.element(find.text('Add new address'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Add new address'), findsOneWidget);
  });

  testWidgets('saved Home shortcut selects the stored address', (tester) async {
    SharedPreferences.setMockInitialValues({
      'movera_home_address': 'Klockarvägen 37',
    });
    String? selected;
    await setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RiderSearchPickupLocation(),
                      ),
                    );
                  },
                  child: const Text('Open pickup'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Klockarvägen 37'), findsOneWidget);
    expect(find.text('Not saved yet'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(selected, 'Klockarvägen 37');
    expect(find.text('Add new address'), findsNothing);
    expect(find.text('Open pickup'), findsOneWidget);
  });

  testWidgets('trip sharing empty state opens emergency contacts', (
    tester,
  ) async {
    final safety = emptySafety();
    await pumpScreen(tester, TripSharePage(controller: safety));
    expect(find.text('No trusted contacts yet'), findsOneWidget);
    expect(
      find.text(
        'Add an emergency contact first, then choose who can follow your rides.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add emergency contact'), findsOneWidget);

    await tester.tap(find.text('Add emergency contact'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency contacts'), findsOneWidget);
    expect(find.text('No emergency contacts yet'), findsOneWidget);
  });

  testWidgets('location suggestions empty state can close the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showPickupLocationBottomSheet(context),
                  child: const Text('Open confirm'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    expect(find.text('No location suggestions'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Open confirm'), findsOneWidget);
    expect(find.text('No location suggestions'), findsNothing);
  });

  testWidgets('privacy connected-apps empty state is designed', (tester) async {
    await pumpScreen(tester, PrivacyPage(controller: emptyProfile()));
    expect(find.byType(MoveraEmptyState), findsOneWidget);
    expect(find.text('No connected apps'), findsOneWidget);
    expect(
      find.text('No third-party apps can read this Movera account yet.'),
      findsOneWidget,
    );
    expectNoFakeProductionData();
  });

  testWidgets('wallet loaded empty balance keeps vouchers unavailable', (
    tester,
  ) async {
    await pumpScreen(tester, const WalletHome());
    expect(find.text('Loading wallet'), findsNothing);
    expect(find.text('Couldn’t load wallet'), findsNothing);
    expect(find.text('Add funds to your wallet'), findsOneWidget);
    expect(find.text('Vouchers unavailable'), findsOneWidget);
    expect(find.textContaining('MOVERA100'), findsNothing);
  });

  testWidgets('delayed wallet read shows loading without balance', (
    tester,
  ) async {
    final delayed = Completer<double>();
    await pumpScreen(
      tester,
      WalletHome(
        wallet: WalletController(
          store: _ScriptedWalletStore(() => delayed.future),
        ),
      ),
      settle: false,
    );

    expect(find.text('Loading wallet'), findsOneWidget);
    expect(find.text('Checking your balance.'), findsOneWidget);
    expect(find.text('Available balance'), findsNothing);
    expect(find.textContaining('kr '), findsNothing);
    expect(find.text('Couldn’t load wallet'), findsNothing);
    expect(find.text('MOVERA'), findsNothing);

    delayed.complete(0);
    await tester.pumpAndSettle();
    expect(find.text('Loading wallet'), findsNothing);
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('0 kr'), findsOneWidget);
  });

  testWidgets('wallet error offers a real retry without raw exceptions', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(
      tester,
      WalletHome(
        wallet: WalletController(
          store: _ScriptedWalletStore(() async {
            calls += 1;
            if (calls == 1) {
              throw StateError('disk-corrupt-xyz');
            }
            return 125;
          }),
        ),
      ),
    );

    expect(find.text('Couldn’t load wallet'), findsOneWidget);
    expect(find.text('Your balance couldn’t be read. Try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('disk-corrupt-xyz'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.text('Available balance'), findsNothing);
    expect(find.text('Loading wallet'), findsNothing);
    expect(find.text('125 kr'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Couldn’t load wallet'), findsNothing);
    expect(find.text('Loading wallet'), findsNothing);
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('125 kr'), findsOneWidget);
  });

  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
  ]) {
    testWidgets(
      'wallet loading fits ${viewport.width.toInt()}x${viewport.height.toInt()}',
      (tester) async {
        final delayed = Completer<double>();
        await pumpScreen(
          tester,
          WalletHome(
            wallet: WalletController(
              store: _ScriptedWalletStore(() => delayed.future),
            ),
          ),
          viewport: viewport,
          settle: false,
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'wallet loading overflowed at ${viewport.width.toInt()}x${viewport.height.toInt()}',
        );
        expect(find.text('Loading wallet'), findsOneWidget);
        expect(find.text('Available balance'), findsNothing);
        expect(find.textContaining('kr '), findsNothing);
        delayed.complete(0);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'wallet error fits ${viewport.width.toInt()}x${viewport.height.toInt()}',
      (tester) async {
        await pumpScreen(
          tester,
          WalletHome(
            wallet: WalletController(
              store: _ScriptedWalletStore(() async {
                throw StateError('disk-corrupt-xyz');
              }),
            ),
          ),
          viewport: viewport,
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'wallet error overflowed at ${viewport.width.toInt()}x${viewport.height.toInt()}',
        );
        expect(find.text('Couldn’t load wallet'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining('disk-corrupt-xyz'), findsNothing);
        expect(find.text('Available balance'), findsNothing);
      },
    );
  }

  Widget Function() screenFor(String name) {
    switch (name) {
      case 'Notifications':
        return () => const NotificationScreen();
      case 'History':
        return () => RideHistory(
          reservations: emptyReservations(),
          onDemandReader: () async => const [],
        );
      case 'Support':
        return () => const SupportHome();
      case 'Profile':
        return () => PrivacyPage(controller: emptyProfile());
      case 'Wallet':
        return () => const WalletHome();
      case 'Upcoming':
        return () => RideHistory(
          reservations: emptyReservations(),
          onDemandReader: () async => const [],
        );
      case 'Saved places':
        return () => const RiderSearchPickupLocation();
      case 'Emergency contacts':
        return () => EmergencyContactsPage(controller: emptySafety());
      case 'Trip sharing':
        return () => TripSharePage(controller: emptySafety());
      case 'Chat':
        return () => const Chat();
      case 'Waiting driver':
        return () => Scaffold(
          body: WaitingDriverCard(
            driver: null,
            onOpenProfile: () {},
            onCall: () {},
            onMore: () {},
          ),
        );
      case 'Tip':
        // Tipping now offers amounts, so the empty state this matrix checks
        // has to be asked for explicitly rather than being the default.
        return () => Scaffold(
          body: RideCompletedAddTip(
            controller: RideCompleteController(
              tips: const TipCatalog(amounts: []),
            ),
          ),
        );
      case 'Receipt':
        return () => const Scaffold(body: RideCompletedTripDetail());
      case 'Completion driver':
        return () => const Scaffold(body: RideCompletedDriverInfo());
      case 'Location suggestions':
        return () => const Scaffold(body: PickupLocationBottomSheet());
      default:
        throw StateError('Unknown empty-state screen: $name');
    }
  }

  const surfaces = <(String, String, String, String?)>[
    (
      'Notifications',
      "You're all caught up.",
      'Ride and account updates will appear here when they arrive.',
      null,
    ),
    (
      'History',
      'No upcoming rides',
      'Whatever is on your schedule, a Scheduled Ride can get you there on time',
      'Schedule a ride',
    ),
    (
      'Support',
      'No rides to review',
      'Your completed and cancelled rides will appear here.',
      'Support messaging',
    ),
    (
      'Profile',
      'No connected apps',
      'No third-party apps can read this Movera account yet.',
      null,
    ),
    (
      'Wallet',
      'Vouchers unavailable',
      'Demo top-ups use simulated payments.',
      'Add funds (demo)',
    ),
    (
      'Upcoming',
      'No upcoming rides',
      'Whatever is on your schedule, a Scheduled Ride can get you there on time',
      'Schedule a ride',
    ),
    (
      'Saved places',
      'No recent trips yet',
      'Completed trips will appear here when real ride history is available.',
      'Not saved yet',
    ),
    (
      'Emergency contacts',
      'No emergency contacts yet',
      'Add someone you trust so they can be reached quickly.',
      'Add contact',
    ),
    (
      'Trip sharing',
      'No trusted contacts yet',
      'Add an emergency contact first, then choose who can follow your rides.',
      'Add emergency contact',
    ),
    (
      'Chat',
      'No messages yet',
      'Your conversation with the driver will appear here when the ride is connected.',
      null,
    ),
    (
      'Waiting driver',
      'Driver details unavailable',
      'Verified driver and vehicle information will appear here when matching confirms them.',
      null,
    ),
    (
      'Tip',
      'Tips unavailable',
      "Tipping isn't available in this build.",
      null,
    ),
    (
      'Receipt',
      'Trip details unavailable',
      'Your route, payment method and price will appear here when the ride record is available.',
      null,
    ),
    (
      'Completion driver',
      'Driver details unavailable',
      'Verified driver and vehicle information will appear here when it is available for this ride.',
      null,
    ),
    (
      'Location suggestions',
      'No location suggestions',
      'Location suggestions aren’t connected in this build yet.',
      'Close',
    ),
  ];

  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
  ]) {
    for (final surface in surfaces) {
      final name = surface.$1;
      final title = surface.$2;
      final message = surface.$3;
      final action = surface.$4;
      testWidgets(
        '$name empty state fits ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (tester) async {
          await pumpScreen(
            tester,
            screenFor(name)(),
            viewport: viewport,
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                '$name overflowed at ${viewport.width.toInt()}x${viewport.height.toInt()}',
          );
          await expectCopy(tester, title, reason: '$name title');
          await expectCopy(
            tester,
            message,
            reason: '$name message',
            containing: true,
          );
          if (action != null) {
            await expectCopy(tester, action, reason: '$name action');
          }
          expect(
            tester.takeException(),
            isNull,
            reason:
                '$name overflowed after revealing empty copy at ${viewport.width.toInt()}x${viewport.height.toInt()}',
          );
          expectNoFakeProductionData();
        },
      );
    }
  }
}

class _ScriptedWalletStore extends WalletStore {
  _ScriptedWalletStore(this._onLoad);

  final Future<double> Function() _onLoad;

  @override
  Future<double> loadBalance() => _onLoad();
}
