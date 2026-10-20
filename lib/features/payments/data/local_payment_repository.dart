import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/domain/payment_repository.dart';

class LocalPaymentRepository implements PaymentRepository {
  LocalPaymentRepository({DefaultPaymentStore? store})
      : _store = store ?? const PrefsDefaultPaymentStore();

  final DefaultPaymentStore _store;
  String _defaultId = 'cash';
  bool _hydrated = false;

  @override
  Future<List<PaymentMethod>> listMethods() async {
    await restore();
    return const [
      PaymentMethod(id: 'wallet', kind: PaymentMethodKind.wallet, label: 'Movera Wallet'),
      PaymentMethod(id: 'apple', kind: PaymentMethodKind.applePay, label: 'Apple Pay'),
      PaymentMethod(id: 'google', kind: PaymentMethodKind.googlePay, label: 'Google Pay'),
      PaymentMethod(id: 'card', kind: PaymentMethodKind.card, label: 'Card'),
      PaymentMethod(id: 'cash', kind: PaymentMethodKind.cash, label: 'Cash'),
    ];
  }

  @override
  Future<void> setDefault(String methodId) async {
    _defaultId = methodId;
    _hydrated = true;
    await _store.save(methodId);
  }

  Future<void> restore() async {
    if (_hydrated) return;
    final saved = await _store.read();
    if (saved != null && saved.isNotEmpty) {
      _defaultId = saved;
    }
    _hydrated = true;
  }

  /// Forgets the signed-out rider's default method in memory.
  @override
  void clearLocal() {
    _defaultId = 'cash';
    _hydrated = false;
  }

  String get defaultId => _defaultId;
}
