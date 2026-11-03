import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/application/support_ticket_repository.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.15 (owner 2026-11-02 "Both"): the admin topics show in Help's first
/// screen and under a past ride's problems; nothing removed, no second
/// "Other"; a picked topic opens the ticket on that topic (with the ride).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final ride = SupportRide(
    id: 'ondemand-trp_1',
    title: 'Till Odenplan',
    when: DateTime(2026, 10, 26, 22, 32),
    price: 54,
    image: 'assets/images/rides/movera.webp',
  );

  testWidgets('Help first screen: topics below the lines, no second Other', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HowCanWeHelp())),
    );
    await tester.pumpAndSettle();
    expect(find.text(L10n.current.supportHelpWithRide), findsOneWidget);
    expect(find.text(L10n.current.supportSomethingElse), findsOneWidget);
    for (final code in supportTopics.where((c) => c != 'other')) {
      expect(find.byKey(ValueKey('support-topic-$code')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('support-topic-other')), findsNothing);
  });

  testWidgets('a past ride keeps its problems and lists the topics below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SelectIssue(ride: ride)));
    await tester.pumpAndSettle();
    for (final issue in SelectIssue.issues) {
      expect(find.text(issue), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('support-topic-lost_item')),
      findsOneWidget,
    );
    final lastIssue = tester.getTopLeft(find.text(SelectIssue.issues.last)).dy;
    final firstTopic = tester
        .getTopLeft(find.byKey(const ValueKey('support-topic-ride_dispute')))
        .dy;
    expect(firstTopic, greaterThan(lastIssue));
  });

  testWidgets('only the topics the server has on', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportTopicLines(load: () async => ['payment', 'other']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-topic-payment')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-topic-lost_item')), findsNothing);
    expect(find.byKey(const ValueKey('support-topic-other')), findsNothing);
  });

  testWidgets('a topic picked on a ride opens the ticket on it with the ride', (
    tester,
  ) async {
    final sent = <Map<String, Object?>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SupportChat(
          contact: const SupportContact(email: ''),
          ride: ride,
          topic: 'lost_item',
          send: ({required rideId, required reason, detail}) async {},
          sendTopic: ({tripId, required category, required text}) async {
            sent.add({'tripId': tripId, 'category': category, 'text': text});
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-message-field')),
      'Glömde min väska',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();
    expect(sent, [
      {'tripId': 'trp_1', 'category': 'lost_item', 'text': 'Glömde min väska'},
    ]);
  });

  test(
    'checker MED3 + owner: the driver app\'s topic names; payment says Betalning for riders',
    () {
      L10n.use('sv');
      addTearDown(() => L10n.use('en'));
      expect(
        [
          for (final code in supportTopics)
            supportTopicLabel(L10n.current, code),
        ],
        [
          'Problem med en resa',
          'Hjälp med appen',
          'Borttappad sak',
          'Betalning',
          'Konto och dokument',
          'Säkerhet',
          'Något annat',
        ],
      );
    },
  );
}
