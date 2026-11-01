enum PaymentMethodKind { wallet, applePay, card, cash }

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.kind,
    required this.label,
    this.detail,
  });

  final String id;
  final PaymentMethodKind kind;
  final String label;
  final String? detail;
}

/// Money never flows through the UI. Implementations live in data/.
///
/// `LocalPaymentRepository` is device-only (demo/dev);
/// `ApiPaymentMethodRepository` reads the rider's methods from the server
/// (ARCH-7, contract C-10, PROPOSED).
abstract class PaymentRepository {
  Future<List<PaymentMethod>> listMethods();
  Future<void> setDefault(String methodId);

  /// Forgets the signed-out rider's methods in memory.
  void clearLocal();
}
