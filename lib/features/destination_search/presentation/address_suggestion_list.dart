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

/// How [AddressSuggestionList] looks.
enum AddressSuggestionStyle {
  /// The #712 look: rows in a rounded card (Schedule ride). Unchanged.
  card,

  /// Saved places v4 (owner 2026-11-27): plain rows on white, the typed
  /// part of the name in bold, ink outlined pins, hairline dividers.
  plain,
}

/// The suggestion rows for [suggester]'s current text.
class AddressSuggestionList extends StatelessWidget {
  const AddressSuggestionList({
    super.key,
    required this.suggester,
    required this.onPick,
    this.empty,
    this.style = AddressSuggestionStyle.card,
    this.onUseCurrentLocation,
    this.currentLocationLabel,
    this.currentLocationDetail,
  });

  final AddressSuggestionStyle style;

  /// [AddressSuggestionStyle.plain] only: when set, a "use current
  /// position" row ([currentLocationLabel]) comes first, typed or not.
  final VoidCallback? onUseCurrentLocation;
  final String? currentLocationLabel;

  /// An optional second line under [currentLocationLabel] (the address).
  final String? currentLocationDetail;

  final AddressSuggester suggester;

  /// The rider chose [suggestion]: its address, and its point when known.
  final void Function(PlaceSuggestion suggestion) onPick;

  /// Shown instead when nothing is typed or the answer has no suggestions;
  /// nothing shows while the first answer is pending.
  final Widget? empty;

  static const Color _ink = Color(0xFF172127);
  static const Color _muted = Color(0xFF6A7278);
  static const Color _line = Color(0xFFE4E7E8);
  static const Color _plainInk = Color(0xFF12201C);
  static const Color _plainMuted = Color(0xFF8A8A8A);
  static const Color _hairline = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: suggester, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    if (style == AddressSuggestionStyle.plain) return _plain();
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

  Widget _plain() {
    final results = suggester.results;
    final typed = suggester.query.trim();
    final Widget body;
    if (typed.isEmpty || (results != null && results.isEmpty)) {
      body = empty ?? const SizedBox.shrink();
    } else if (results == null) {
      body = const SizedBox.shrink();
    } else {
      body = Column(
        key: const ValueKey('address-suggestions'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in results.indexed)
            InkWell(
              key: ValueKey('address-suggestion-$i'),
              onTap: () => onPick(s),
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _hairline)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: _plainInk,
                      size: 22,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            boldMatch(s.title, typed),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (s.subtitle.isNotEmpty)
                            Text(
                              s.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: _plainMuted,
                                fontSize: 13,
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
      );
    }
    final current = onUseCurrentLocation;
    if (current == null) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('address-use-current'),
          onTap: current,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                const Icon(Icons.my_location, color: _plainInk, size: 22),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentLocationLabel ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: _plainInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (currentLocationDetail?.isNotEmpty == true)
                        Text(
                          currentLocationDetail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: _plainMuted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body,
      ],
    );
  }

  /// [title] with the first case-insensitive match of [typed] in bold.
  static TextSpan boldMatch(String title, String typed) {
    final base = GoogleFonts.poppins(color: _plainInk, fontSize: 16);
    final bold = base.copyWith(fontWeight: FontWeight.w600);
    final at = typed.isEmpty
        ? -1
        : title.toLowerCase().indexOf(typed.toLowerCase());
    if (at < 0) return TextSpan(text: title, style: base);
    final end = at + typed.length;
    return TextSpan(
      style: base,
      children: [
        if (at > 0) TextSpan(text: title.substring(0, at)),
        TextSpan(text: title.substring(at, end), style: bold),
        if (end < title.length) TextSpan(text: title.substring(end)),
      ],
    );
  }
}
