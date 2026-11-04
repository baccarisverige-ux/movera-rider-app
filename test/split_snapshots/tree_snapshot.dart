import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Base job 2 (split the biggest screens, no behaviour change): a text
/// "screenshot" of a pumped screen — every widget type in tree order, the
/// laid-out size and position of every box, and every text and icon. It is
/// written once before the split (`flutter test --update-goldens`) and must
/// match unchanged after it. Plain text, so it is the same on every machine.
String treeSnapshot(WidgetTester tester) {
  final out = StringBuffer();
  void visit(Element element, int depth) {
    final widget = element.widget;
    final line = StringBuffer('${'  ' * depth}${widget.runtimeType}');
    if (widget is Text) {
      line.write(' "${widget.data ?? widget.textSpan?.toPlainText()}"');
    }
    if (widget is RichText) {
      line.write(' "${widget.text.toPlainText()}"');
    }
    if (widget is Icon) {
      line.write(' icon=${widget.icon?.codePoint}');
    }
    if (widget is EditableText) {
      line.write(' "${widget.controller.text}"');
    }
    final render = element.renderObject;
    if (element is RenderObjectElement &&
        render is RenderBox &&
        render.hasSize) {
      final at = render.attached ? render.localToGlobal(Offset.zero) : null;
      line.write(' size=${_r(render.size.width)}x${_r(render.size.height)}');
      if (at != null) line.write(' at=${_r(at.dx)},${_r(at.dy)}');
    }
    // Clock times ("13:02") follow the wall clock, not the code.
    out.writeln(
      line.toString().replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), 'HH:MM'),
    );
    element.visitChildren((child) => visit(child, depth + 1));
  }

  visit(tester.binding.rootElement!, 0);
  return out.toString();
}

String _r(double v) => v.isFinite ? v.toStringAsFixed(1) : '$v';

/// Compares with (or, with --update-goldens, writes) test/split_snapshots/[name].txt.
void expectTreeSnapshot(WidgetTester tester, String name) {
  final file = File('test/split_snapshots/$name.txt');
  final now = treeSnapshot(tester);
  if (autoUpdateGoldenFiles) {
    file.writeAsStringSync(now);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Run flutter test --update-goldens once to write $name.txt',
  );
  expect(
    now,
    file.readAsStringSync(),
    reason: 'The $name screen changed: $name.txt',
  );
}
