import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/saved_places/application/quick_save.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'check_log.dart';
import 'rider_session.dart';
import 'rider_steps.dart';
import 'type_text.dart';

/// Saved-places fixed category proof (contract 0.18.129, rider #651-#653,
/// owner 2026-11-18 design steps 2-5) on a real Test Lab phone against
/// staging (testlab_test `saved-places`, MOVERA_TL_SCENARIO=places):
///
/// START, SIGN-IN, PLACES-BEFORE (the rider's server places, never
/// touched), RECENT (a recent address that is not saved: Where to once on a
/// fresh install), POPUP, RECENT-TAP (categories screen), SAVE-SHEET
/// ("Spara adressen?" up within ~1 s; screenshot), SAVE-TYPE (Gym ->
/// "Sparad som Gym"), ASK-CATEGORY ("Alltid välja kategori ...?" -> Komfort;
/// screenshot), SAVED-TAP (Home -> pop-up -> the Gym place: the categories
/// list is never drawn, Set pickup opens with Komfort and "Byt kategori";
/// screenshot), SERVER (the place and its fixed category on the server),
/// CLEANUP (only the places this run created are deleted over HTTP).
class PlacesRun extends RiderSession {
  PlacesRun(super.tester, super.log);

  static const Duration hardAfter = Duration(minutes: 9);
  static const Duration testLimit = Duration(minutes: 13);

  /// "Within ~1 s" (owner): the sheet must be fully up this soon after the
  /// categories screen is on screen (pump granularity 50 ms included).
  static const Duration sheetLimit = Duration(milliseconds: 1500);

  final DateTime startedAt = DateTime.now();
  bool _written = false;

  /// Server placeIds before the run (null = not readable: no clean-up).
  Set<String>? placesBefore;
  String? chosenId;
  String? chosenName;

  Future<void> step(
    String id,
    String title,
    Future<void> Function() body,
  ) async {
    if (pastStepsHardStop) {
      return log.skip(id, title, 'not run: hard time limit (clean-up next)');
    }
    log.step(id);
    CheckLog.missed = null;
    try {
      await body();
    } catch (error, stack) {
      log.fail(id, title, 'stopped by ${error.runtimeType}: $error');
      CheckLog.say('STACK ${stack.toString().split('\n').take(5).join(' | ')}');
    }
  }

  bool _failedSince(int n) =>
      log.results.skip(n).any((r) => r.outcome == CheckOutcome.fail);

  Future<void> all({required String phone, required String code}) async {
    stepsHardStop = startedAt.add(hardAfter);
    secretValues
      ..clear()
      ..addAll([phone, code]);
    try {
      await start();
      final used = await pumpUntil(
        tester,
        () => clientInUse,
        timeout: const Duration(seconds: 30),
        dismiss: false,
      );
      used
          ? log.pass('START', 'app starts with the recording client', 'ok')
          : log.fail(
              'START',
              'app starts with the recording client',
              'no call',
            );
      final error = await guard(() => signIn(tester, phone: phone, code: code));
      if (error != null) {
        return log.fail('SIGN-IN', 'test rider reaches Home', error);
      }
      if (!await adoptAppSession()) {
        return log.fail('SIGN-IN', 'test rider reaches Home', 'no session');
      }
      log.pass('SIGN-IN', 'test rider reaches Home', 'Home on a fresh install');
      // Let the app's first saved-places sync land.
      await wait(tester, const Duration(seconds: 4));
      await step('PLACES-BEFORE', 'server places read before', _before);
      // The first picture converts the surface (slow once): on Home, which
      // shows no number, so the timed pictures below are fast.
      await log.screenshot(tester, 'home');
      final n = log.results.length;
      await step('RECENT', 'a recent address that is not saved', _recent);
      if (_failedSince(n)) return;
      await step('POPUP', 'places pop-up opens from Home', _popup);
      if (_failedSince(n)) return;
      await step(
        'RECENT-TAP',
        'recent address opens the categories',
        _tapRecent,
      );
      if (_failedSince(n)) return;
      await step('SAVE-SHEET', '"Spara adressen?" up within ~1 s', _sheet);
      if (_failedSince(n)) return;
      await step('SAVE-TYPE', 'Gym saves the place', _saveGym);
      if (_failedSince(n)) return;
      await step('ASK-CATEGORY', 'fixed category asked; Komfort', _fix);
      if (chosenId == null) return;
      await step('SAVED-TAP', 'saved place skips the categories', _savedTap);
      await step('SERVER', 'place and category on the server', _server);
    } catch (error, stack) {
      log.fail('RUN', 'checks ran to the end', 'stopped by $error');
      CheckLog.say('STACK ${stack.toString().split('\n').take(6).join(' | ')}');
    } finally {
      stepsHardStop = null;
      await _cleanup();
    }
  }

  Future<List<Map<String, dynamic>>?> _serverPlaces() async {
    refreshRiderToken();
    final answer = await riderApi.places();
    final items = answer.map?['items'];
    if (!answer.ok || items is! List) return null;
    return [
      for (final i in items)
        if (i is Map<String, dynamic>) i,
    ];
  }

  Future<void> _before() async {
    final places = await _serverPlaces();
    if (places == null) {
      return log.fail(
        'PLACES-BEFORE',
        'server places read before',
        'GET failed',
      );
    }
    placesBefore = {for (final p in places) '${p['placeId']}'};
    log.pass(
      'PLACES-BEFORE',
      'server places read before',
      '${places.length} place(s) before the run (never touched)',
    );
  }

  Finder get _recentRow => byKey('places-popup-recent-0');

  Future<bool> _openPopup() async {
    if (!await tapKey(tester, 'home-places')) return false;
    return pumpUntil(
      tester,
      () => tester.any(byKey('places-popup').hitTestable()),
      timeout: const Duration(seconds: 10),
    );
  }

  Future<void> _closePopup() async {
    await systemBack(tester);
    await pumpUntil(tester, () => !shows(byKey('places-popup')));
  }

  /// A fresh install has no recents: one Where to pick (Stureplan) up to
  /// the categories and back makes one.
  Future<void> _recent() async {
    const title = 'a recent address that is not saved';
    await backToHome(tester);
    if (!await _openPopup()) {
      return log.fail('RECENT', title, 'pop-up did not open');
    }
    final had = shows(_recentRow);
    await _closePopup();
    if (had) {
      return log.pass('RECENT', title, 'the pop-up already lists one');
    }
    if (!await tapKey(tester, 'home-where-to')) {
      return log.fail('RECENT', title, 'Where to not tappable');
    }
    final field = find.descendant(
      of: byKey('route-picker-field-destination'),
      matching: find.byType(EditableText),
    );
    await pumpUntil(
      tester,
      () => shows(find.byType(RoutePickerPage)) && shows(field),
      timeout: const Duration(seconds: 15),
    );
    if (!shows(field)) {
      return log.fail('RECENT', title, 'Where to did not open');
    }
    await typeText(tester, field.first, dropoffQuery);
    final row = byKeyPrefix('route-picker-row-');
    if (!await pumpUntil(tester, () => tester.any(row.hitTestable()))) {
      return log.fail('RECENT', title, 'no suggestion row in 30 s');
    }
    await tapHit(tester, row, 'suggestion row');
    await pumpUntil(
      tester,
      () => shows(find.byType(SelectRide)),
      timeout: const Duration(seconds: 30),
    );
    await wait(tester, const Duration(seconds: 2));
    await backToHome(tester, tries: 5);
    await wait(tester, const Duration(seconds: 1));
    if (!await _openPopup()) {
      return log.fail('RECENT', title, 'pop-up did not open again');
    }
    final now = shows(_recentRow);
    await _closePopup();
    now
        ? log.pass('RECENT', title, 'made by one Where to pick ($dropoffQuery)')
        : log.fail('RECENT', title, 'no recent row after a Where to pick');
  }

  Future<void> _popup() async {
    await backToHome(tester);
    (await _openPopup()) && shows(_recentRow)
        ? log.pass(
            'POPUP',
            'places pop-up opens from Home',
            'recent row listed',
          )
        : log.fail('POPUP', 'places pop-up opens from Home', 'no pop-up/row');
  }

  Future<void> _tapRecent() async {
    const title = 'recent address opens the categories';
    if (!await tapHit(tester, _recentRow, '"places-popup-recent-0"')) {
      return log.fail('RECENT-TAP', title, 'recent row not tappable');
    }
    final ok = await pumpUntil(
      tester,
      () => shows(find.byType(SelectRide)),
      timeout: const Duration(seconds: 30),
      step: const Duration(milliseconds: 50),
    );
    ok
        ? log.pass('RECENT-TAP', title, 'categories screen shown')
        : log.fail('RECENT-TAP', title, 'categories not shown in 30 s');
  }

  bool _sheetUp() {
    final dim = byKey('place-save-dim');
    if (!shows(dim) ||
        !tester.any(byKey('place-save-type-gym').hitTestable())) {
      return false;
    }
    final box = tester.widget<ColoredBox>(dim.first);
    return box.color.a >= 0.195;
  }

  Future<void> _sheet() async {
    const title = '"Spara adressen?" up within ~1 s';
    final clock = Stopwatch()..start();
    final up = await pumpUntil(
      tester,
      _sheetUp,
      timeout: const Duration(seconds: 10),
      step: const Duration(milliseconds: 50),
    );
    clock.stop();
    final ms = clock.elapsedMilliseconds;
    final question = L10n.current.placesSaveAddress;
    final text = shows(find.text(question));
    await log.screenshot(tester, 'save-sheet');
    if (!up) {
      return log.fail('SAVE-SHEET', title, 'sheet not up in 10 s');
    }
    final detail =
        'fully up $ms ms after the categories screen showed '
        '(limit ${sheetLimit.inMilliseconds} ms); "$question" shown=$text';
    up && text && clock.elapsed <= sheetLimit
        ? log.pass('SAVE-SHEET', title, detail)
        : log.fail('SAVE-SHEET', title, detail);
  }

  Future<void> _saveGym() async {
    const title = 'Gym saves the place';
    if (!await tapHit(tester, byKey('place-save-type-gym'), 'Gym chip')) {
      return log.fail('SAVE-TYPE', title, 'Gym chip not tappable');
    }
    final saved = L10n.current.placesSavedAs(PlaceQuickSave.label('gym'));
    final ok = await pumpUntil(
      tester,
      () => shows(find.text(saved)),
      timeout: const Duration(seconds: 4),
      step: const Duration(milliseconds: 100),
    );
    ok
        ? log.pass('SAVE-TYPE', title, '"$saved" shown')
        : log.fail('SAVE-TYPE', title, '"$saved" not shown in 4 s');
  }

  Future<void> _fix() async {
    const title = 'fixed category asked; Komfort';
    final ask = L10n.current.placesAskFixCategory;
    final chips = byKeyPrefix('place-save-category-');
    final ok = await pumpUntil(
      tester,
      () => shows(find.text(ask)) && tester.any(chips.hitTestable()),
      timeout: const Duration(seconds: 3),
      step: const Duration(milliseconds: 100),
    );
    if (!ok) return log.fail('ASK-CATEGORY', title, '"$ask" not shown');
    final offered = <(String, String)>[
      for (final e in chips.evaluate())
        if (e.widget.key case final ValueKey<String> k)
          (
            k.value.substring('place-save-category-'.length),
            textsUnder(find.byKey(k)).join(' '),
          ),
    ];
    final komfort = offered
        .where(
          (c) => RegExp(
            'komfort|comfort',
            caseSensitive: false,
          ).hasMatch('${c.$1} ${c.$2}'),
        )
        .firstOrNull;
    final pick = komfort ?? offered.first;
    await log.screenshot(tester, 'ask-category');
    if (!await tapHit(
      tester,
      byKey('place-save-category-${pick.$1}'),
      'category chip',
    )) {
      return log.fail('ASK-CATEGORY', title, 'chip not tappable');
    }
    chosenId = pick.$1;
    chosenName = pick.$2;
    await pumpUntil(
      tester,
      () => !shows(byKey('place-save-sheet')),
      timeout: const Duration(seconds: 3),
    );
    final detail =
        '"$ask" shown; offered=${[for (final c in offered) c.$2]}; '
        'picked "${pick.$2}"';
    komfort != null
        ? log.pass('ASK-CATEGORY', title, detail)
        : log.fail('ASK-CATEGORY', title, 'Komfort not offered; $detail');
  }

  Future<void> _savedTap() async {
    const title = 'saved place skips the categories';
    await backToHome(tester, tries: 5);
    await wait(tester, const Duration(seconds: 2));
    if (!await _openPopup()) {
      return log.fail('SAVED-TAP', title, 'pop-up did not open');
    }
    final gym = byKey(
      'places-popup-place-custom-${PlaceQuickSave.label('gym')}',
    );
    if (!await pumpUntil(
      tester,
      () => shows(gym),
      timeout: const Duration(seconds: 5),
    )) {
      return log.fail('SAVED-TAP', title, 'Gym place not in the pop-up');
    }
    await log.screenshot(tester, 'popup-saved');
    if (!await tapHit(tester, gym, 'Gym place row')) {
      return log.fail('SAVED-TAP', title, 'Gym place not tappable');
    }
    var tilesSeen = false;
    var holding = false;
    final tiles = byKeyPrefix('select-ride-tile-');
    final opened = await pumpUntil(
      tester,
      () {
        if (shows(tiles)) tilesSeen = true;
        if (shows(byKey('select-ride-preferred-holding'))) holding = true;
        return tester.any(byKey('set-pickup-confirm').hitTestable());
      },
      timeout: const Duration(seconds: 40),
      step: const Duration(milliseconds: 50),
    );
    await wait(tester, const Duration(milliseconds: 800));
    if (shows(tiles)) tilesSeen = true;
    final change = shows(byKey('set-pickup-change-category'));
    final sheetTexts = textsUnder(byKey('set-pickup-sheet'));
    final name = (chosenName ?? '').trim();
    final hasName = name.isNotEmpty && sheetTexts.any((t) => t.contains(name));
    await log.screenshot(tester, 'set-pickup-fixed');
    final detail =
        'Set pickup open=${opened && shows(find.byType(SetPickupPage))} '
        'categories list drawn=$tilesSeen holding screen=$holding '
        '"${L10n.current.placesChangeCategory}"=$change "$name" shown=$hasName';
    opened && !tilesSeen && change && hasName
        ? log.pass('SAVED-TAP', title, detail)
        : log.fail('SAVED-TAP', title, detail);
  }

  List<Map<String, dynamic>> _mine(List<Map<String, dynamic>> places) {
    final before = placesBefore;
    if (before == null) return const [];
    return [
      for (final p in places)
        if (!before.contains('${p['placeId']}')) p,
    ];
  }

  Future<void> _server() async {
    const title = 'place and category on the server';
    List<Map<String, dynamic>> mine = const [];
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      final places = await _serverPlaces();
      mine = places == null ? const [] : _mine(places);
      if (mine.any((p) => p['preferredCategoryId'] == chosenId)) break;
      await wait(tester, const Duration(seconds: 2));
    }
    final hit = mine.where((p) => p['preferredCategoryId'] == chosenId);
    final detail =
        'new place(s)=${mine.length} type=${[for (final p in mine) p['type']]} '
        'preferredCategoryId matches=${hit.isNotEmpty}';
    hit.isNotEmpty
        ? log.pass('SERVER', title, detail)
        : log.fail('SERVER', title, detail);
  }

  /// Deletes only the places this run created (not in [placesBefore]).
  Future<void> _cleanup() async {
    const title = 'places this run saved are deleted';
    if (placesBefore == null) {
      return log.skip('CLEANUP', title, 'no snapshot before: nothing deleted');
    }
    final places = await _serverPlaces();
    if (places == null) return log.fail('CLEANUP', title, 'GET failed');
    final mine = _mine(places);
    final codes = <int>[];
    for (final p in mine) {
      codes.add((await riderApi.deletePlace('${p['placeId']}')).status);
    }
    final after = await _serverPlaces();
    final left = after == null ? -1 : _mine(after).length;
    final detail = 'deleted ${mine.length} (status $codes); left=$left';
    left == 0
        ? log.pass('CLEANUP', title, detail)
        : log.fail('CLEANUP', title, detail);
  }

  Future<void> writeResults() async {
    if (_written) return;
    _written = true;
    await log.write(requestLog: [for (final c in rec.calls) '$c']);
    log.end();
  }
}
