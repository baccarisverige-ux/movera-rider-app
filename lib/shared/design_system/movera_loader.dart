import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';

class MoveraLoader extends StatelessWidget {
  const MoveraLoader({super.key, this.title, this.message});

  /// Defaults to "Loading" / "Just a moment." in the app language.
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MoveraEmptyState(
      icon: Icons.hourglass_empty_rounded,
      title: title ?? context.l10n.loaderTitle,
      message: message ?? context.l10n.loaderMessage,
    );
  }
}
