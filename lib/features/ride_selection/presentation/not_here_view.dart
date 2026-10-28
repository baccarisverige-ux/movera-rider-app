import 'package:flutter/material.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.11.0 §21 (owner 2026-10-28): the pickup lies outside every
/// open zone. A clear message, not an error, and no way to book: "Movera
/// finns inte här än", the zones where Movera runs in the app language,
/// and a way back to change the pickup.
class NotHereView extends StatelessWidget {
  const NotHereView({super.key, this.onChangePickup});

  /// Back to change the pickup; the route is popped without one.
  final VoidCallback? onChangePickup;

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _accent = Color(0xFF2D5878);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final names = RiderZones.cityNames(L10n.code);
    return Scaffold(
      key: const ValueKey('not-here'),
      backgroundColor: const Color(0xFFF6F5F1),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: l10n.back,
                  onPressed: () => _back(context),
                  icon: const Icon(Icons.arrow_back, color: _ink),
                ),
              ),
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE6EEF3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wrong_location_outlined,
                    size: 44,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                l10n.notHereTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.notHereBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: _muted),
              ),
              if (names.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.notHereZones(names.join(', ')),
                  key: const ValueKey('not-here-zones'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const ValueKey('not-here-change-pickup'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _back(context),
                  child: Text(
                    l10n.notHereChangePickup,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _back(BuildContext context) {
    final change = onChangePickup;
    if (change != null) {
      change();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}
