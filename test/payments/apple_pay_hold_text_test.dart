import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// Fix-now Q5 (owner): the Apple Pay / Google Pay line says when the money is
/// held and when it is taken, as the contract's payment flow does
/// (pending -> authorized at the search, authorized -> captured at the end).
void main() {
  test('the wallet-pay line says held at the search, charged at the end', () {
    expect(
      lookupAppLocalizations(const Locale('en')).paysWhenSearchStarts,
      'The amount is held when the search starts and charged when the ride '
      'ends',
    );
    expect(
      lookupAppLocalizations(const Locale('fr')).paysWhenSearchStarts,
      'Le montant est réservé au début de la recherche et débité à la fin de '
      'la course',
    );
    expect(
      lookupAppLocalizations(const Locale('sv')).paysWhenSearchStarts,
      'Beloppet reserveras när sökningen börjar och dras när resan är klar',
    );
  });
}
