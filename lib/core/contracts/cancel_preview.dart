import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

/// What [CancelPreview.feeNow] / `feeAfterFree` is: a cancel fee or, after
/// the driver's free waiting, the no-show fee.
enum CancelPreviewKind { cancel, noShow }

/// The fee a cancel costs at one moment, read off the server's preview.
class CancelPreviewNow {
  const CancelPreviewNow({
    required this.fee,
    required this.kind,
    this.freeUntil,
  });

  final Money fee;
  final CancelPreviewKind kind;

  /// When the free cancel ends, while it has not ended yet; else null.
  final DateTime? freeUntil;
}

/// `TripProjection.cancelPreview` (contract v0.18.92
/// `priceDisplay.cancelPreview`, BQ-M22): what a rider cancel costs now,
/// worked out by the server with the trip's kept rules, and the one step
/// ahead (`freeUntil` → `feeAfterFree`, `kindAfterFree`). The app compares
/// the clock with [freeUntil] and never works a fee out itself.
class CancelPreview {
  const CancelPreview({
    required this.feeNow,
    required this.kind,
    this.freeUntil,
    this.feeAfterFree,
    this.kindAfterFree,
  });

  final Money feeNow;
  final CancelPreviewKind kind;
  final DateTime? freeUntil;
  final Money? feeAfterFree;
  final CancelPreviewKind? kindAfterFree;

  /// Null when absent (an older server, no rule) or not well formed.
  static CancelPreview? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final feeNow = Money.fromWire(raw['feeNow']);
    final kind = _kind(raw['kind']);
    if (feeNow == null || kind == null) return null;
    final freeUntil = WireTime.tryParse(raw['freeUntil']);
    final after = Money.fromWire(raw['feeAfterFree']);
    // feeAfterFree comes with freeUntil; one without the other is no step.
    final step = freeUntil != null && after != null;
    return CancelPreview(
      feeNow: feeNow,
      kind: kind,
      freeUntil: step ? freeUntil : null,
      feeAfterFree: step ? after : null,
      kindAfterFree: step ? _kind(raw['kindAfterFree']) : null,
    );
  }

  static CancelPreviewKind? _kind(Object? raw) => switch (raw) {
    'cancel' => CancelPreviewKind.cancel,
    'no_show' => CancelPreviewKind.noShow,
    _ => null,
  };

  /// The same preview with [freeUntil] moved by [toDevice] (a server stamp
  /// onto the device clock).
  CancelPreview onDevice(DateTime Function(DateTime) toDevice) => CancelPreview(
    feeNow: feeNow,
    kind: kind,
    freeUntil: freeUntil == null ? null : toDevice(freeUntil!),
    feeAfterFree: feeAfterFree,
    kindAfterFree: kindAfterFree,
  );

  /// The fee at [now]: [feeNow] before [freeUntil], [feeAfterFree] (with
  /// [kindAfterFree], else [kind]) from it on. A clock compare, no maths.
  CancelPreviewNow at(DateTime now) {
    final until = freeUntil;
    final after = feeAfterFree;
    if (until != null && after != null && !now.isBefore(until)) {
      return CancelPreviewNow(fee: after, kind: kindAfterFree ?? kind);
    }
    return CancelPreviewNow(fee: feeNow, kind: kind, freeUntil: until);
  }
}
