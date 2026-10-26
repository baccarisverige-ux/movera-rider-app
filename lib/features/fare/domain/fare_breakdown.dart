class FareBreakdown {
  const FareBreakdown({
    required this.baseMinor,
    required this.distanceMinor,
    required this.timeMinor,
    required this.bookingFeeMinor,
    this.waitingMinor = 0,
    this.surgeMinor = 0,
    this.airportMinor = 0,
    this.tollsMinor = 0,
    this.taxMinor = 0,
    this.promotionMinor = 0,
    this.walletCreditMinor = 0,
  });

  final int baseMinor;
  final int distanceMinor;
  final int timeMinor;
  final int bookingFeeMinor;
  final int waitingMinor;
  final int surgeMinor;
  final int airportMinor;
  final int tollsMinor;
  final int taxMinor;
  final int promotionMinor;
  final int walletCreditMinor;

  int get finalMinor =>
      baseMinor +
      distanceMinor +
      timeMinor +
      bookingFeeMinor +
      waitingMinor +
      surgeMinor +
      airportMinor +
      tollsMinor +
      taxMinor -
      promotionMinor -
      walletCreditMinor;
}
