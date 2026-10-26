import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';

Future<void> showDriverCallUnavailable(
  BuildContext context, {
  String? driverName,
}) {
  final name = driverName?.trim();
  final driverLabel = name == null || name.isEmpty
      ? context.l10n.yourDriver
      : name;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.callUnavailableTitle),
      content: Text(context.l10n.callUnavailableBody(driverLabel)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );
}
