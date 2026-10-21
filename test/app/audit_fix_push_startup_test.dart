import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/bootstrap.dart';

void main() {
  testWidgets('rider-5: push re-registration starts after the first frame '
      'and nothing waits for it', (tester) async {
    final calls = <String>[];
    final slowNetwork = Completer<void>();
    startPushAfterFirstFrame(
      startCoordinator: () async => calls.add('coordinator'),
      registerExisting: () {
        calls.add('register');
        return slowNetwork.future;
      },
    );
    expect(calls, isEmpty, reason: 'nothing runs before a frame is painted');
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['coordinator', 'register']);
  });
}
