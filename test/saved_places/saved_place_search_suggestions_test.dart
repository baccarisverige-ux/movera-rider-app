import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finder B9 (Saved places > Add Home/Work): the address search showed no
/// suggestions while typing, always showed the two empty boxes ("No recent
/// trips yet", "No search results … Suggestions aren't available yet"),
/// and the field said "Pickup location" while saving a Home address.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String?> open(
    WidgetTester tester, {
    List<String> recent = const [],
    List<PlaceSuggestion> suggestions = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? picked;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => RiderSearchPickupLocation(
                      recentAddresses: () async => recent,
                      suggest: (_) async => suggestions,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('typing shows address suggestions; a tap picks one', (
    tester,
  ) async {
    await open(
      tester,
      suggestions: const [
        PlaceSuggestion(
          title: 'Drottninggatan 53',
          subtitle: '111 21 Stockholm',
        ),
      ],
    );
    expect(find.text('No search results'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Drottning');
    await tester.pump(RiderSearchPickupLocation.suggestDebounce);
    await tester.pumpAndSettle();
    expect(find.text('Drottninggatan 53'), findsOneWidget);
    expect(find.text('No search results'), findsNothing);
    await tester.tap(find.text('Drottninggatan 53'));
    await tester.pumpAndSettle();
    expect(find.byType(RiderSearchPickupLocation), findsNothing);
  });

  testWidgets('a lookup that found nothing says so', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(RiderSearchPickupLocation.suggestDebounce);
    await tester.pumpAndSettle();
    expect(find.text('No search results'), findsOneWidget);
  });

  testWidgets('recent addresses are listed instead of the empty box', (
    tester,
  ) async {
    await open(tester, recent: const ['Odenplan, Stockholm']);
    expect(find.text('Odenplan, Stockholm'), findsOneWidget);
    expect(find.text('No recent trips yet'), findsNothing);
  });

  testWidgets('the field says address, not pickup location', (tester) async {
    await open(tester);
    expect(find.text('Pickup location'), findsNothing);
    expect(find.text('Search address'), findsWidgets);
  });
}
