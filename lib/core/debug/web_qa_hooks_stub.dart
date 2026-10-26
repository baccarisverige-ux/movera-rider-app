/// No-op QA hooks for VM / non-web builds.
void reportRestoreSurface(String surface) {}

void reportHomeBuilt() {}

void reportMapOwner(String? owner, int generation) {}

void reportPuckHeading(double heading, {required bool compass}) {}

void reportSafetySnapshot(String json) {}

void installSafetyQaOpener(void Function() open) {}

void installSafetyNavigationBridge(bool Function() open) {}

void reportSearchSnapshot(String json) {}

void installMatchingQaHooks({
  required void Function() hold,
  required void Function() assign,
  required void Function(int seconds) advance,
}) {}

void installRideCheckQaHook() {}

void installFrameTimingQaHook() {}

String? pendingRideCheckType() => null;

String? pendingRideCheckDetail() => null;

void clearPendingRideCheck() {}

void listenForRideCheckQa(void Function()? listener) {}

void reportRideCheckSnapshot(String json) {}
