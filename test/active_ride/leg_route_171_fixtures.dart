import 'package:google_maps_flutter/google_maps_flutter.dart';

/// v0.18.171 test lines around Stockholm (Sergels torg to Medborgarplatsen).
const pickupPoint = LatLng(59.3326, 18.0649);
const dropoffPoint = LatLng(59.3143, 18.0735);
const carPoint = LatLng(59.3400, 18.0500);

/// The driver's road to the pickup: a dog-leg, not a straight line.
const pickupLegPoints = <LatLng>[
  carPoint,
  LatLng(59.3400, 18.0560),
  LatLng(59.3360, 18.0600),
  LatLng(59.3330, 18.0640),
  pickupPoint,
];

/// The road to the drop-off, from the pickup.
const dropoffLegPoints = <LatLng>[
  pickupPoint,
  LatLng(59.3270, 18.0700),
  LatLng(59.3200, 18.0720),
  dropoffPoint,
];

/// Google encoded polyline, precision 5.
String encodeLine(List<LatLng> points) {
  final out = StringBuffer();
  var lat = 0;
  var lng = 0;
  void value(int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in points) {
    final la = (p.latitude * 1e5).round();
    final ln = (p.longitude * 1e5).round();
    value(la - lat);
    value(ln - lng);
    lat = la;
    lng = ln;
  }
  return out.toString();
}

Map<String, Object?> pickupLegJson() => {
  'target': 'pickup',
  'polyline': encodeLine(pickupLegPoints),
};

Map<String, Object?> dropoffLegJson() => {
  'target': 'dropoff',
  'polyline': encodeLine(dropoffLegPoints),
};
