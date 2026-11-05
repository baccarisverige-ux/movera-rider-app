part of 'support.dart';

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: SupportHome.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: SupportHome.text(14, height: 1.4, color: Colors.white),
        ),
      ),
    );
  }
}

class _SupportScaffold extends StatelessWidget {
  const _SupportScaffold({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: SupportHome.ink,
                    ),
                    tooltip: context.l10n.back,
                  ),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  title,
                  style: SupportHome.text(
                    28,
                    weight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

Widget _exit(BuildContext context) {
  return TextButton(
    onPressed: () => Navigator.popUntil(context, AppRoutes.isHomeRoute),
    child: Text(
      context.l10n.supportExit,
      style: SupportHome.text(
        14,
        weight: FontWeight.w600,
        color: SupportHome.accent,
      ),
    ),
  );
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, this.onTap, this.compact = false});

  final SupportRide ride;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: SupportHome.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              ride.image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_car_filled_rounded,
                color: SupportHome.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SupportHome.text(14.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  ride.whenLabel,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
                Text(
                  ride.priceLabel,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.onTap});

  final SupportRide ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: SupportHome.soft,
              child: Icon(
                ride.failed || ride.cancelled
                    ? Icons.no_crash_outlined
                    : Icons.directions_car_filled_outlined,
                color: SupportHome.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SupportHome.text(14.5, weight: FontWeight.w600),
                  ),
                  Text(
                    ride.whenLabel,
                    style: SupportHome.text(12.5, color: SupportHome.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // rider-u230: a cancelled ride reads as on the other Support
              // screens (its fee, not the full fare).
              ride.cancelled
                  ? ride.priceLabel
                  : ride.failed
                  ? context.l10n.supportFailed
                  // rider-r5-48: an ended-early charge to the öre.
                  : formatMajor(
                      ride.price,
                      ride.currency,
                      whole: !ride.endedEarly,
                    ),
              style: SupportHome.text(14, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTrip extends StatelessWidget {
  const _CompactTrip({required this.ride});

  final SupportRide ride;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_car_filled_outlined,
            color: SupportHome.ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.title,
                  style: SupportHome.text(14, weight: FontWeight.w600),
                ),
                Text(
                  ride.longWhen,
                  style: SupportHome.text(12.5, color: SupportHome.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SupportHome.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupportHome.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SupportHome.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SupportHome.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: SupportHome.text(
                    13,
                    color: SupportHome.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupportHome.soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: SupportHome.text(15, weight: FontWeight.w600),
                ),
              ),
              Icon(icon, color: SupportHome.accent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.accent = false,
  });

  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: icon == null ? null : Icon(icon, color: SupportHome.ink),
          title: Text(
            title,
            style: SupportHome.text(
              15.5,
              weight: FontWeight.w500,
              color: accent ? SupportHome.accent : SupportHome.ink,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: accent ? SupportHome.accent : SupportHome.muted,
          ),
        ),
        const Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: SupportHome.line,
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: SupportHome.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: SupportHome.text(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SupportHome.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupportHome.soft,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: SupportHome.ink),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SupportHome.text(13.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamAvatars extends StatelessWidget {
  const _TeamAvatars();

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF2D5878), Color(0xFF4A7A96), Color(0xFF1D252C)];
    return SizedBox(
      width: 86,
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              left: i * 22.0,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colors[i],
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiraMark extends StatelessWidget {
  const _MiraMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF2D5878),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
    );
  }
}

/// Loads the rider's rides once and builds with them; a short spinner
/// while loading, the empty state when the history cannot be read.
class _SupportRides extends StatefulWidget {
  const _SupportRides({required this.load, required this.builder});

  final SupportRidesLoader load;
  final Widget Function(BuildContext context, List<SupportRide> rides) builder;

  @override
  State<_SupportRides> createState() => _SupportRidesState();
}

class _SupportRidesState extends State<_SupportRides> {
  late Future<List<SupportRide>> _rides = _load();

  Future<List<SupportRide>> _load() =>
      widget.load().timeout(const Duration(seconds: 8));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SupportRide>>(
      future: _rides,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // rider-r3-2: a history that could not be read is not "no rides".
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmptyCard(
                icon: Icons.cloud_off_outlined,
                title: context.l10n.historyLoadFailed,
                subtitle: context.l10n.historyLoadFailedBody,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _rides = _load();
                  }),
                  child: Text(context.l10n.retry),
                ),
              ),
            ],
          );
        }
        return widget.builder(context, snapshot.data ?? const []);
      },
    );
  }
}
