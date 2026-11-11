import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
        final canConfirm =
            confirmText == null || controller.text.trim() == confirmText;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.danger, width: 1.2),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: const TextStyle(color: Colors.white70)),
                if (confirmText != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Confirm karne ke liye "$confirmText" type karein:',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
              child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
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
