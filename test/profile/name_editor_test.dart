import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';

/// Q3: an empty name is not saved ("Enter your name"); Done saves.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<String? Function()> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? saved = 'not closed';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showAccountTextEditor(
                context,
                title: 'Name',
                value: 'Sara',
                emptyError: 'Enter your name',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => saved;
  }

  testWidgets('an empty name is blocked with Enter your name', (tester) async {
    final saved = await open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(saved(), 'not closed');
    // Typing clears the message; Save then closes with the name.
    await tester.enterText(find.byType(TextField), ' Lina ');
    await tester.pump();
    expect(find.text('Enter your name'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved(), 'Lina');
  });

  testWidgets('the keyboard Done key saves', (tester) async {
    final saved = await open(tester);
    await tester.enterText(find.byType(TextField), 'Lina');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved(), 'Lina');
  });

  testWidgets('Done on an empty name shows the message and stays', (
    tester,
  ) async {
    final saved = await open(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(saved(), 'not closed');
  });
}
