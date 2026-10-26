import 'dart:async';

class PlaceSearchService {
  PlaceSearchService({this.delay = const Duration(milliseconds: 320)});

  final Duration delay;
  Timer? _timer;
  int _generation = 0;

  void query(String text, void Function(String value, int generation) onReady) {
    _timer?.cancel();
    final generation = ++_generation;
    _timer = Timer(delay, () => onReady(text, generation));
  }

  bool isCurrent(int generation) => generation == _generation;

  void dispose() {
    _timer?.cancel();
    _generation++;
  }
}
