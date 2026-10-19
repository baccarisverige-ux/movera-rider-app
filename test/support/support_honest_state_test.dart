import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/application/support_controller.dart';
import 'package:movera_rider/features/support/data/support_repository.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('support repository contains no seeded rides or live-agent claim',
      () async {
    final repository = SupportRepository();
    final controller = SupportController(
      store: repository,
      onDemand: () async => const [],
      scheduled: () => const [],
    );
    final script = controller.chat();

    // FLOW-8: rides come only from the rider's own history.
    expect(await controller.loadRides(), isEmpty);
    // UI-09: no build-state wording; UI-03: points to the ride list.
    expect(script.welcome, contains('choose the ride'));
    expect(script.welcome, isNot(contains('connected')));
    expect(script.followUp, contains('Sent to Movera'));
    expect(script.welcome, isNot(contains('Mira')));
    expect(script.followUp, isNot(contains('agent will take it')));
  });

  testWidgets('Support home shows an honest empty ride state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SupportHome()));
    await tester.pumpAndSettle();

    expect(find.text('Help'), findsOneWidget);
    expect(find.text('No rides to review'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(
      find.text('Your completed and cancelled rides will appear here.'),
      findsOneWidget,
    );
    expect(find.text('Browse all help topics'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Support messaging'), 180);
    expect(find.text('Support messaging'), findsOneWidget);

    expect(find.textContaining('Arlanda'), findsNothing);
    expect(find.textContaining('Södertälje'), findsNothing);
    expect(find.textContaining('Stureplan'), findsNothing);
    expect(find.textContaining('SEK 612'), findsNothing);
  });

  testWidgets('Support messages contain no fabricated active or closed cases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SupportMessages()));
    await tester.pumpAndSettle();

    expect(find.text('No active cases'), findsOneWidget);
    expect(
      find.text('Messages you send about a ride go to the Movera team for review.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('No closed cases'), 160);
    expect(find.text('No closed cases'), findsOneWidget);
    expect(
      find.text('You have no closed support cases.'),
      findsOneWidget,
    );
    expect(find.text('I was charged for cancellation'), findsNothing);
    expect(find.text('I want to cancel my delayed order'), findsNothing);
    expect(find.text('29 October 2024'), findsNothing);
  });

  testWidgets('Support chat without a ride points to the ride list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SupportChat(contact: SupportContact(email: '')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('choose the ride'), findsOneWidget);
    expect(find.text('Support messaging unavailable'), findsNothing);
    expect(find.text('Choose a ride'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('agent will take it'), findsNothing);
  });

  testWidgets(
    'UI-03: with no support email a ride issue is sent from the app',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sent = <Map<String, String?>>[];
      var fail = true;

      await tester.pumpWidget(
        MaterialApp(
          home: SupportChat(
            contact: const SupportContact(email: ''),
            ride: SupportRide(
              id: 'ondemand-ride_42',
              title: 'To Arlanda',
              when: DateTime(2026, 10, 1, 9, 30),
              price: 659,
              image: 'assets/images/rides/movera.webp',
            ),
            issue: 'I was charged twice',
            send: ({required rideId, required reason, detail}) async {
              if (fail) {
                fail = false;
                throw StateError('offline');
              }
              sent.add({'rideId': rideId, 'reason': reason, 'detail': detail});
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Support messaging unavailable'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
      await tester.enterText(find.byType(TextField), 'Two charges on my card');
      await tester.tap(find.byKey(const ValueKey('support-message-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('support-message-error')), findsOneWidget);
      expect(sent, isEmpty);

      await tester.tap(find.byKey(const ValueKey('support-message-send')));
      await tester.pumpAndSettle();
      expect(sent, [
        {
          'rideId': 'ride_42',
          'reason': 'charged_twice',
          'detail': 'I was charged twice\nTwo charges on my card',
        },
      ]);
      expect(find.byKey(const ValueKey('support-message-sent')), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    },
  );
}
