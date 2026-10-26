import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';

/// Phase 132 cluster 3: 4-digit PIN validation was duplicated with the same
/// ^\d{4}$ regex in phone_verify.dart and auth_repository.dart instead of
/// reusing RidePin. Both now call [RidePin.isValidFormat], the same
/// predicate RidePin.isAvailable and RidePin.fromJson already used.
void main() {
  bool oldRegex(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  test('isValidFormat matches the old inline regex for typical inputs', () {
    for (final value in ['1234', '0000', '12345', '123', 'abcd', '', '12a4']) {
      expect(RidePin.isValidFormat(value), oldRegex(value));
    }
  });

  test('isAvailable and fromJson still key off the same 4-digit shape', () {
    expect(
      const RidePin(pinId: 'p', userId: 'u', pin: '9821').isAvailable,
      isTrue,
    );
    expect(
      const RidePin(pinId: 'p', userId: 'u', pin: '98a1').isAvailable,
      isFalse,
    );
    expect(
      RidePin.fromJson({'pinId': 'p', 'userId': 'u', 'pin': '4471'}).pin,
      '4471',
    );
    expect(
      RidePin.fromJson({'pinId': 'p', 'userId': 'u', 'pin': 'bad'}).pin,
      '',
    );
  });
}
