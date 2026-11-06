import 'dart:collection';

/// v0.18.42 §67 (same-address fix, proven cause): the labels of the address
/// suggestions the server offered, with their place ids. When the rider picks
/// one, its label is what the flows geocode; [placeIdFor] lets that geocode
/// ask by place id (the server then answers the place itself, with its name)
/// and tells the app to keep the chosen label instead of the street address.
class PickedPlaces {
  PickedPlaces({this.capacity = 200});

  /// The one the suggestion list and the geocoder share.
  static final PickedPlaces shared = PickedPlaces();

  final int capacity;
  final LinkedHashMap<String, String> _ids = LinkedHashMap<String, String>();

  static String _key(String label) => label.trim().toLowerCase();

  void remember(String label, String placeId) {
    final key = _key(label);
    if (key.isEmpty || placeId.isEmpty) return;
    _ids.remove(key);
    _ids[key] = placeId;
    while (_ids.length > capacity) {
      _ids.remove(_ids.keys.first);
    }
  }

  String? placeIdFor(String label) => _ids[_key(label)];

  void clear() => _ids.clear();
}
