/// The fare a stand-in server ride holds, in kronor, for assertions:
/// `fare: Money` (contract v0.3.0), or the pre-v0.3 `price` a test seeded
/// and the server has not rewritten.
num? mockFareKr(Map<String, dynamic>? ride) {
  final fare = ride?['fare'];
  if (fare is Map && fare['amountMinor'] is int) {
    return (fare['amountMinor'] as int) / 100;
  }
  return ride?['price'] as num?;
}
