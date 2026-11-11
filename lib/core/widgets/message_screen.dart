import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Full-screen message with an optional action, used for loading/blocked/
/// error states (e.g. "account not set up", "cafe suspended").
class MessageScreen extends StatelessWidget {
  const MessageScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  /// Plain loading screen.
  static Widget loading([String text = 'Loading…']) => Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.palette.canvas,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: Space.lg),
                Text(text, style: TextStyle(color: context.palette.inkSubtle)),
              ],
            ),
          ),
        ),
      );

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = iconColor ?? p.warning;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 34, color: c),
                ),
                const SizedBox(height: Space.lg),
                Text(title, textAlign: TextAlign.center, style: context.text.headlineSmall),
                const SizedBox(height: Space.sm),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: p.inkSubtle, height: 1.4)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: Space.xl),
                  OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
