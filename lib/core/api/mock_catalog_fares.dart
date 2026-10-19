/// Dev fallback fares in whole kronor, shared by the in-process mock server
/// and the catalog fallback quote repository. Lives in core so the mock
/// transport does not import a feature (ARCH-17).
const mockCatalogPricesKr = <String, int>{
  'economy': 259,
  'comfort': 339,
  'premium': 369,
  'priority': 289,
  'xl': 399,
  'electric': 259,
  'pet': 279,
};
