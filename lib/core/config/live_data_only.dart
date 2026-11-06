/// L-a R1/R3 (owner Q5 A, 2026-11-06): on a live build (staging,
/// production) the app shows only what the server said. Until the server's
/// zones arrive there are no built-in sample zones, and a built-in list
/// price is never shown as a price: the screen says "Checking your area…".
/// Demo, dev and test builds keep the samples. Set once at start-up
/// (bootstrap) from `!AppEnv.allowsMockTransport`; tests set it directly.
abstract final class LiveDataOnly {
  static bool on = false;
}
