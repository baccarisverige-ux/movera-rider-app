import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../integration_test/staging/check_log.dart';
import '../../integration_test/staging/smooth_verdict.dart';

/// Owner 2026-11-22: a frame check (SMOOTH) judged WARN is shown in the
/// summary and never counts as a failure; PASS and FAIL stay as they were.
/// Runs the real [CheckLog] (no source reading).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  CheckLog newLog() => CheckLog(binding: binding, outDir: null, shots: false);

  /// Runs [body] and returns the lines it printed.
  Future<List<String>> printed(Future<void> Function() body) async {
    final lines = <String>[];
    await runZonedPrint(body, lines);
    return lines;
  }

  test('a WARN is in the results, not in the failures', () {
    final log = newLog();
    log.smooth('TRANSITION:home:SMOOTH', SmoothOutcome.warn, 'smooth', 'x');
    expect(log.results.single.outcome, CheckOutcome.warn);
    expect(log.failures, isEmpty);
  });

  test('PASS and FAIL keep their outcome', () {
    final log = newLog();
    log.smooth('TRANSITION:a:SMOOTH', SmoothOutcome.pass, 'smooth', 'x');
    log.smooth('TRANSITION:b:SMOOTH', SmoothOutcome.fail, 'smooth', 'x');
    expect(log.results.map((r) => r.outcome), [
      CheckOutcome.pass,
      CheckOutcome.fail,
    ]);
    expect(log.failures.single.id, 'TRANSITION:b:SMOOTH');
  });

  test('the build is said at the start and the summary counts WARN', () async {
    final lines = await printed(() async {
      final log = newLog();
      log.smooth('TRANSITION:a:SMOOTH', SmoothOutcome.warn, 'smooth', 'x');
      log.pass('RELOAD', 'reload', 'ok');
      await log.write(requestLog: const []);
    });
    expect(lines.first, '${CheckLog.prefix} ${SmoothVerdict.buildLine()}');
    expect(
      lines,
      contains(
        '${CheckLog.prefix} SUMMARY passed=1 failed=0 skipped=0 warned=1',
      ),
    );
  });
}

Future<void> runZonedPrint(Future<void> Function() body, List<String> out) =>
    runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => out.add(line),
      ),
    );
