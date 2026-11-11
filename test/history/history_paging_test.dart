import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// History showed nothing until up to 5 pages were read one after another,
/// and never showed trips older than page 5. Page 1 now shows at once and
/// older pages load when the list nears its end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> trip(int n) => {
    'tripId': 'trip_$n',
    'status': 'completed',
    'fare': {'amountMinor': 10000 + n, 'currency': 'SEK'},
    'pickup': {'address': 'Pickup $n', 'lat': 59.34, 'lng': 18.05},
    'destination': {'address': 'Stop $n', 'lat': 59.65, 'lng': 17.93},
    'endedAt': DateTime.utc(
      2026,
      10,
      1,
    ).subtract(Duration(hours: n)).toIso8601String(),
  };

  /// 7 pages of 8 trips; page `p` is answered by [gates] when given.
  ({
    ApiRideHistoryRepository repo,
    List<String?> cursors,
    Map<int, Completer<void>> gates,
  })
  server() {
    final cursors = <String?>[];
    final gates = <int, Completer<void>>{};
    final api = ApiClient(
      client: MockClient((request) async {
        final cursor = request.url.queryParameters['cursor'];
        cursors.add(cursor);
        final page = cursor == null ? 0 : int.parse(cursor.substring(1));
        await gates[page]?.future;
        if (page == 99) return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'items': [for (var i = 0; i < 8; i++) trip(page * 8 + i)],
            'nextCursor': page < 6 ? 'p${page + 1}' : null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (
      repo: ApiRideHistoryRepository(api: api),
      cursors: cursors,
      gates: gates,
    );
  }

  test('one page per read, with its next cursor', () async {
    final s = server();
    final first = await s.repo.loadOnDemandPage();
    expect(first.items, hasLength(8));
    expect(first.nextCursor, 'p1');
    final last = await s.repo.loadOnDemandPage(cursor: 'p6');
    expect(last.nextCursor, isNull);
    expect(s.cursors, [null, 'p6']);
  });

  Future<void> pump(WidgetTester tester, ApiRideHistoryRepository repo) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandPageReader: (cursor) => repo.loadOnDemandPage(cursor: cursor),
        ),
      ),
    );
  }

  testWidgets('page 1 shows at once; older pages load on scroll, to the end', (
    tester,
  ) async {
    final s = server();
    await pump(tester, s.repo);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Completed').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Stop 0'), findsWidgets);
    // Only page 1 was read before anything showed.
    expect(s.cursors, [null]);

    for (
      var i = 0;
      i < 30 && find.textContaining('Stop 55').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Stop 55'), findsWidgets);
    expect(s.cursors, [null, 'p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
    expect(find.byKey(const ValueKey('history-more-loading')), findsNothing);
  });

  testWidgets('a failed older page shows Retry and reads it again', (
    tester,
  ) async {
    final s = server();
    var fail = true;
    Future<RideHistoryPage> failing(String? cursor) async {
      if (cursor == 'p1' && fail) throw StateError('offline');
      return s.repo.loadOnDemandPage(cursor: cursor);
    }

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandPageReader: failing,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Completed').first);
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 10 && find.text('Retry').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('history-more-failed')), findsOneWidget);
    expect(find.text('Couldn’t load rides'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Completed').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('history-more-failed')), findsNothing);
    expect(find.textContaining('Stop 8'), findsWidgets);
  });
}
