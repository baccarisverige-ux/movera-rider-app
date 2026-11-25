import 'dart:async';

import 'package:movera_rider/shared/widgets/slot_motion.dart';

/// The looping panel animations stay still in tests so `pumpAndSettle`
/// settles; their own tests switch them on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SlotMotion.enabled = false;
  await testMain();
}
