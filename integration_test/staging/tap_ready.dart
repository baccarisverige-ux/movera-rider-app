import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// G31 phone run 1 (BOOK FAIL: no POST /trips): the test tapped "Confirm
/// and search" as soon as it was hit-testable and enabled. Set pickup is
/// still sliding in then, and the app ignores a tap on purpose while its
/// screen opens (set_pickup_page.dart `_confirm`, P5-R6: the second tap
/// of a double tap must not book). A button is ready for the rider's tap
/// only once its own route has finished opening.
bool readyToTap(WidgetTester tester, Finder button) {
  if (!tester.any(button.hitTestable())) return false;
  final widget = tester.widget(button.first);
  if (widget is ButtonStyleButton && widget.onPressed == null) return false;
  final route = ModalRoute.of(tester.element(button.first));
  final opening = route?.animation;
  return opening == null || opening.isCompleted;
}
