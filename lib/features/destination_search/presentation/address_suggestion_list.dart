import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';

/// Address suggestions while typing, from the same autocomplete "Where to?"
/// uses (`DestinationSearchController.suggest`, POST
/// /api/v1/locations/autocomplete): one request once typing pauses
/// ([RoutePickerPage.suggestDebounce]), and an answer for an older query is
/// never shown. The screen calls [type] from its field's `onChanged`, as
/// "Where to?" does. Used by Schedule ride and Save address.
class AddressSuggester extends ChangeNotifier {
  AddressSuggester({this.near});

  final GeoPoint? near;
  Timer? _debounce;
  bool _disposed = false;
  String _query = '';
  List<PlaceSuggestion> _results = const [];
  String _resultsQuery = '';

  String get query => _query;

  /// The answer for the text typed now; null while it is pending.
  List<PlaceSuggestion>? get results =>
      _resultsQuery == _query ? _results : null;

  void type(String value) {
    _query = value;
    _debounce?.cancel();
    notifyListeners();
    if (value.trim().isEmpty) return;
    _debounce = Timer(RoutePickerPage.suggestDebounce, () {
      if (_disposed || value != _query) return;
      unawaited(
        AppScope.instance.destinationSearch.suggest(
          value,
          near: near,
          onReady: (query, results) => _answer(query, results),
          onFailed: (query) => _answer(query, const []),
        ),
      );
    });
  }

  /// Stop showing suggestions (a pick was made), without a new lookup.
  void clear() {
    _debounce?.cancel();
    _query = '';
    _results = const [];
    _resultsQuery = '';
    notifyListeners();
  }

  void _answer(String query, List<PlaceSuggestion> results) {
    if (_disposed || query != _query) return;
    _results = results;
    _resultsQuery = query;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

/// The suggestion rows for [suggester]'s current text.
class AddressSuggestionList extends StatelessWidget {
  const AddressSuggestionList({
    super.key,
    required this.suggester,
    required this.onPick,
    this.empty,
  });

  final AddressSuggester suggester;

  /// The rider chose [suggestion]: its address, and its point when known.
  final void Function(PlaceSuggestion suggestion) onPick;

  /// Shown instead when nothing is typed or the answer has no suggestions;
  /// nothing shows while the first answer is pending.
  final Widget? empty;

  static const Color _ink = Color(0xFF172127);
  static const Color _muted = Color(0xFF6A7278);
  static const Color _line = Color(0xFFE4E7E8);

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: suggester, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final results = suggester.results;
    if (suggester.query.trim().isEmpty ||
        (results != null && results.isEmpty)) {
      return empty ?? const SizedBox.shrink();
    }
    if (results == null) return const SizedBox.shrink();
    return _rows(results);
  }

  Widget _rows(List<PlaceSuggestion> results) {
    return Container(
      key: const ValueKey('address-suggestions'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in results.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 48, color: _line),
            InkWell(
              key: ValueKey('address-suggestion-$i'),
              onTap: () => onPick(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: _muted,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (s.subtitle.isNotEmpty)
                            Text(
                              s.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
