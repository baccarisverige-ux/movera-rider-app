import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner, 2026-10-28: a help ticket written without choosing a ride says
/// nothing about a ride, neither in the intro nor after sending. With a
/// ride the ride texts stay.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> sendText(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('support-message-field')),
      'Hjälp mig',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('without a ride: intro and reply do not mention a ride', (
    tester,
  ) async {
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    await tester.pumpWidget(
      MaterialApp(
        home: SupportChat(
          contact: const SupportContact(email: ''),
          sendHelp: ({required text}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Berätta vad du behöver hjälp med.'), findsOneWidget);
    expect(find.text(L10n.current.supportWelcomeGeneral), findsNothing);
    expect(find.text(L10n.current.supportIssueAck), findsNothing);
    await sendText(tester);
    expect(find.text('Tack! Vi svarar så snart vi kan.'), findsOneWidget);
    expect(find.text(L10n.current.supportFollowUp), findsNothing);
  });

  testWidgets('with a ride: the ride texts stay', (tester) async {
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    await tester.pumpWidget(
      MaterialApp(
        home: SupportChat(
          contact: const SupportContact(email: ''),
          ride: SupportRide(
            id: 'ondemand-trp_1',
            title: 'Till Odenplan',
            when: DateTime(2026, 10, 26, 22, 32),
            price: 54,
            image: 'assets/images/rides/movera.webp',
          ),
          send: ({required rideId, required reason, detail}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Berätta vad som hände på resan.'), findsOneWidget);
    expect(find.text(L10n.current.supportIssueAck), findsOneWidget);
    await sendText(tester);
    expect(
      find.text(
        'Skickat till Movera. Teamet granskar det tillsammans med '
        'uppgifterna om resan.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tack! Vi svarar så snart vi kan.'), findsNothing);
  });

  test('English and French no-ride texts', () {
    addTearDown(() => L10n.use('en'));
    L10n.use('en');
    expect(
      L10n.current.supportWelcomeTicket,
      'Tell us what you need help with.',
    );
    expect(
      L10n.current.supportFollowUpTicket,
      "Thanks! We'll answer as soon as we can.",
    );
    L10n.use('fr');
    expect(
      L10n.current.supportWelcomeTicket,
      'Dites-nous ce dont vous avez besoin.',
    );
    expect(
      L10n.current.supportFollowUpTicket,
      'Merci ! Nous répondons dès que possible.',
    );
  });
}
