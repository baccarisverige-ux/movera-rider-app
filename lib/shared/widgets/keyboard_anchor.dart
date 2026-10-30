import 'package:flutter/material.dart';

/// Keeps a form's main button (and what sits between it and the field)
/// in view right above the on-screen keyboard.
///
/// Owner 2026-10-30 (rider sign-in video on an iPhone): "When clic on any
/// box to fill, why the botton continue doesnt show up with keyboard!?"
/// Tapping the phone field opened the keyboard, the page scrolled only far
/// enough to show the field (Flutter's own caret scroll), and the terms
/// tick and Continue stayed under the keyboard.
///
/// Wrap the main button of a form whose fields scroll with it. Whenever
/// the keyboard covers part of the screen (`MediaQuery.viewInsets.bottom`,
/// which Flutter web fills from `window.visualViewport` on iPhone Safari
/// and Android Chrome while a field is edited, and the OS fills in the
/// store apps) and a text field of the same scroll view has focus, the
/// page jumps so this button sits just above the keyboard; the focused
/// field is then kept on screen too (it wins when both cannot fit).
///
/// A jump, not an animation: the caret scroll Flutter starts at the same
/// moment would otherwise cancel it half-way.
class KeyboardAnchor extends StatefulWidget {
  const KeyboardAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardAnchor> createState() => _KeyboardAnchorState();
}

class _KeyboardAnchorState extends State<KeyboardAnchor>
    with WidgetsBindingObserver {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_schedule);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _schedule();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A new size reaches this subtree through MediaQuery.
    MediaQuery.sizeOf(context);
    _schedule();
  }

  /// After the next layout, when the new inset has shrunk the page.
  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _reveal();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _reveal() {
    if (!mounted) return;
    // The view's own inset: inside a Scaffold body MediaQuery has it
    // removed already (the body is the part above the keyboard).
    final view = View.of(context);
    if (view.viewInsets.bottom <= 0) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !focused.mounted) return;
    if (focused.findAncestorStateOfType<EditableTextState>() == null &&
        focused.widget is! EditableText) {
      return;
    }
    final mine = Scrollable.maybeOf(context);
    if (mine == null) return;
    // Only the field of this form: a field in a sheet or another page has
    // its own scroll view.
    if (!identical(Scrollable.maybeOf(focused)?.position, mine.position)) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    Scrollable.ensureVisible(
      focused,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
