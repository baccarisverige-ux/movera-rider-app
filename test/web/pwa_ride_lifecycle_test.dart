import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/web/web_ride_pagehide_policy.dart';

void main() {
  test('persisted pagehide preserves an active installed-PWA ride', () {
    expect(shouldHandleRidePageHide(persisted: true), isFalse);
  });

  test('real page teardown still invokes ride cleanup', () {
    expect(shouldHandleRidePageHide(persisted: false), isTrue);
  });
}
