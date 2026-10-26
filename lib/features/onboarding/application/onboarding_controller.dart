import 'package:movera_rider/features/onboarding/data/onboarding_repository.dart';

class OnboardingController {
  OnboardingController({OnboardingRepository? store})
    : _store = store ?? OnboardingRepository();
  final OnboardingRepository _store;

  bool get skipToHome => true;

  Future<void> markSeen() => _store.markSeen();
}
