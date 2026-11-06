import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';

import 'tree_snapshot.dart';

// Base split (owner 2026-11-05, rule 25 "Split everything first"): the Help
// screens of support.dart, written before the split and unchanged after it.

final _ride = SupportRide(
  id: 'ondemand-trp_1',
  title: 'Till Odenplan',
  when: DateTime(2026, 10, 26, 22, 32),
  price: 54,
  image: 'assets/images/rides/movera.webp',
);

Future<List<SupportRide>> _rides() async => [_ride];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(WidgetTester tester, Widget home, String name) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(home: home));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expectTreeSnapshot(tester, name);
  }

  testWidgets('support home', (tester) async {
    await shot(tester, SupportHome(loadRides: _rides), 'rider_support_home');
  });

  testWidgets('select a ride', (tester) async {
    await shot(
      tester,
      SelectSupportRide(loadRides: _rides),
      'rider_support_select_ride',
    );
  });

  testWidgets('select an issue', (tester) async {
    await shot(tester, SelectIssue(ride: _ride), 'rider_support_select_issue');
  });

  testWidgets('help articles', (tester) async {
    await shot(tester, const HelpArticles(), 'rider_support_help_articles');
  });

  testWidgets('support chat on a ride', (tester) async {
    await shot(
      tester,
      SupportChat(
        ride: _ride,
        issue: 'Lost item',
        send: ({required rideId, required reason, detail}) async {},
      ),
      'rider_support_chat',
    );
  });
}
