import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/data/local_payment_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';

void main() {
  test('default payment method survives a new repository instance', () async {
    final memory = MemoryDefaultPaymentStore();
    final first = LocalPaymentRepository(store: memory);
    await first.setDefault('swish');

    final second = LocalPaymentRepository(store: memory);
    await second.restore();
    expect(second.defaultId, 'swish');
  });

  test('ride selection restores the saved payment brand', () async {
    final memory = MemoryDefaultPaymentStore('cards');
    final selection = RideSelectionController(paymentStore: memory);
    // Cash is the default until the saved choice is restored.
    expect(selection.payments()[selection.selectedPayment].brand, 'cash');

    await selection.restoreDefaultPayment();
    expect(selection.payments()[selection.selectedPayment].brand, 'cards');

    selection.selectPayment(
      selection.payments().indexWhere((item) => item.brand == 'cash'),
    );
    expect(memory.value, 'cash');
  });
}
