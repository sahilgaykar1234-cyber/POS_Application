import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Confirmation for destructive actions. When [confirmText] is set, the user
/// must type it exactly before the confirm button is enabled, which prevents
/// accidental one-tap data loss.
///
/// Returns `true` only if the user confirmed.
Future<bool> showDangerConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? confirmText,
}) async {
  final controller = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final p = ctx.palette;
        final canConfirm = confirmText == null || controller.text.trim() == confirmText;
        return AlertDialog(
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.dangerTint, shape: BoxShape.circle),
            child: Icon(Icons.warning_amber_rounded, color: p.danger),
          ),
          title: Text(title, textAlign: TextAlign.center),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: TextStyle(color: p.inkMuted)),
                  if (confirmText != null) ...[
                    const SizedBox(height: Space.lg),
                    Text('Type "$confirmText" to confirm:', style: TextStyle(color: p.inkSubtle, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(controller: controller, autofocus: true, onChanged: (_) => setDialogState(() {})),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: context.onStatusFill),
              onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );

  // Not disposing `controller` here on purpose: the dialog's exit animation can
  // still rebuild the TextField after pop, and a disposed controller would throw.
  return result ?? false;
}

/// Simple yes/no confirmation (non-destructive).
Future<bool> showConfirmDialog(BuildContext context,
    {required String title, required String message, String confirmLabel = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, style: TextStyle(color: ctx.palette.inkMuted)),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return r ?? false;
}
