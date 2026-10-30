/// What the provider's SDK gave the app: the identity token the server
/// verifies (`POST /auth/provider { provider, idToken, app }`, contract §8)
/// and the name Apple shows only the first time (sent as `name`).
class ProviderIdentityToken {
  const ProviderIdentityToken({
    required this.provider,
    required this.idToken,
    this.name,
  });

  final String provider;
  final String idToken;
  final String? name;
}

/// Apple or Google cannot give a token on this build: the button then says
/// "coming soon – use your phone number", like the driver app and like a
/// server without provider keys (`503 provider_not_configured`).
class ProviderUnavailable implements Exception {
  const ProviderUnavailable(this.provider, [this.cause]);
  final String provider;
  final Object? cause;

  @override
  String toString() => 'ProviderUnavailable($provider, $cause)';
}

/// Gets the identity token from Apple or Google. Null when the rider
/// closed the provider's sheet without choosing an account.
abstract class ProviderTokenSource {
  Future<ProviderIdentityToken?> obtain(String provider);
}

/// Owner G1-E "Keep 'coming soon'" and G1-B1 "Fix it (Recommended)": the
/// rider app has no Apple or Google SDK set up yet (no app keys), so every
/// build answers [ProviderUnavailable] and never sends a request without a
/// token (the old build sent `{ provider }` alone and got a 400). Once the
/// SDKs are set up, a source that returns their token plugs in here.
class NoProviderTokenSource implements ProviderTokenSource {
  const NoProviderTokenSource();

  @override
  Future<ProviderIdentityToken?> obtain(String provider) async =>
      throw ProviderUnavailable(provider);
}
