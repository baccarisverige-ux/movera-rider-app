import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';

/// RiderProfileUpdate.language is a code (contracts/openapi.yaml:
/// `^[a-z]{2}(-[A-Z]{2})?$`). The default used to be 'English', which the
/// server rejects.
void main() {
  final code = RegExp(r'^[a-z]{2}(-[A-Z]{2})?$');

  test('a new profile sends the code en, not English', () {
    final body = SyncedProfileRepository.body(RiderProfileData.defaults());
    expect(body['language'], 'en');
    expect(code.hasMatch(body['language'] as String), isTrue);
  });

  test('a profile saved with a language name reads back as its code', () {
    expect(RiderProfileData.fromJson({'language': 'English'}).language, 'en');
    expect(RiderProfileData.fromJson({'language': 'Svenska'}).language, 'sv');
    expect(RiderProfileData.fromJson({'language': 'Français'}).language, 'fr');
    expect(RiderProfileData.fromJson({}).language, 'en');
  });

  test('a code the rider picked is kept', () {
    for (final value in ['en', 'fr', 'sv']) {
      expect(RiderProfileData.fromJson({'language': value}).language, value);
    }
  });
}
