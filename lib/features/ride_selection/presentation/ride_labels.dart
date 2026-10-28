import 'package:movera_rider/l10n/l10n.dart';

/// A ride category's note as the rider reads it: the built-in (and mock
/// catalog) English notes are translated, any other text the admin wrote
/// is shown as it is (rider-77).
String rideNoteFor(String note) => switch (note) {
  'Affordable and convenient rides' => L10n.current.rideNoteEconomy,
  'Newer cars with extra legroom' => L10n.current.rideNoteComfort,
  'Premium cars with top-rated drivers' => L10n.current.rideNotePremium,
  'More options, less waiting' => L10n.current.rideNotePriority,
  'Cars for larger groups (6 people)' => L10n.current.rideNoteXl,
  'Quiet and fossil-free cars' => L10n.current.rideNoteElectric,
  'Pet-friendly rides' => L10n.current.rideNotePet,
  'Groups and luggage' => L10n.current.rideNoteVan,
  'Ramp or lift, driver helps on board' => L10n.current.rideNoteWheelchair,
  'Quiet ride, receipt for your company' => L10n.current.rideNoteBusiness,
  'Fixed price, flight tracked, extra luggage' => L10n.current.rideNoteAirport,
  'Child seat already fitted' => L10n.current.rideNoteKids,
  'A woman behind the wheel' => L10n.current.rideNoteWomen,
  'Send a parcel across town' => L10n.current.rideNoteDelivery,
  _ => note,
};

/// A ride category's name as the rider reads it (owner 2026-10-28): the
/// built-in catalog's plain English names are translated; brand names
/// ("Movera", "Movera XL", "Movera Pet"), "Premium" and any name the admin
/// wrote are shown as they are. The stored name stays the category's.
String rideNameFor(String name) => switch (name.trim()) {
  'Comfort' => L10n.current.categoryComfort,
  'Priority' => L10n.current.categoryPriority,
  'Electric' => L10n.current.categoryElectric,
  'Van' => L10n.current.categoryVan,
  'Wheelchair' => L10n.current.categoryWheelchair,
  'Business' => L10n.current.categoryBusiness,
  'Airport' => L10n.current.categoryAirport,
  'Kids seat' => L10n.current.categoryKidsSeat,
  'Women driver' => L10n.current.categoryWomenDriver,
  'Delivery' => L10n.current.categoryDelivery,
  _ => name,
};

/// A ride category's badge: the built-in RECOMMENDED and FASTER read as
/// the list's filter chips do, in capitals; other badges as they are.
String rideBadgeFor(String badge) => switch (badge) {
  'RECOMMENDED' => L10n.current.filterRecommended.toUpperCase(),
  'FASTER' => L10n.current.filterFaster.toUpperCase(),
  _ => badge,
};
