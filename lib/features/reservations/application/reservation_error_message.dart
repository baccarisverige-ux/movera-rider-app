import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What the rider was doing to a scheduled ride when it failed.
enum ReservationAction { book, edit, cancel }

/// A specific, honest message for a failed scheduled-ride action, always
/// saying what state the ride is left in.
///
/// These failures used to be silent: the button stopped spinning and nothing
/// told the rider whether the ride was booked, changed or still on.
String reservationErrorMessage(Object error, ReservationAction action) {
  if (error is ScheduledQuoteRequiredException) {
    return action == ReservationAction.edit
        ? L10n.current.resErrNoPriceEdit
        : L10n.current.resErrNoPriceBook;
  }
  if (error is ReservationsUnavailableException) {
    return L10n.current.resErrUnavailable;
  }
  final kind = riderErrorKind(error);
  final l = L10n.current;
  return switch (action) {
    ReservationAction.cancel => switch (kind) {
      RiderErrorKind.offline => l.resErrCancelOffline,
      RiderErrorKind.rateLimited => l.resErrCancelRate(_tryAgain(error)),
      RiderErrorKind.serverTrouble => l.resErrCancelServer,
      RiderErrorKind.refused => l.resErrCancelRefused,
      RiderErrorKind.unknown => l.resErrCancelUnknown,
    },
    ReservationAction.book => switch (kind) {
      RiderErrorKind.offline => l.resErrBookOffline,
      RiderErrorKind.rateLimited =>
        l.resErrBookRate(_capitalised(_tryAgain(error))),
      RiderErrorKind.serverTrouble => l.resErrBookServer,
      RiderErrorKind.refused => l.resErrBookRefused,
      RiderErrorKind.unknown => l.resErrBookUnknown,
    },
    ReservationAction.edit => switch (kind) {
      RiderErrorKind.offline => l.resErrEditOffline,
      RiderErrorKind.rateLimited =>
        l.resErrEditRate(_capitalised(_tryAgain(error))),
      RiderErrorKind.serverTrouble => l.resErrEditServer,
      RiderErrorKind.refused => l.resErrEditRefused,
      RiderErrorKind.unknown => l.resErrEditUnknown,
    },
  };
}

String _tryAgain(Object error) {
  final wait = riderRetryWait(error);
  return wait == null
      ? L10n.current.retryInAMoment
      : L10n.current.retryIn(wait);
}

String _capitalised(String text) => text[0].toUpperCase() + text.substring(1);
