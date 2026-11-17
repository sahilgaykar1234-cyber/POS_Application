import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'tr.dart';

/// Language choice as chips (Settings).
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.instance,
      builder: (context, current, _) => Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final l in AppLanguage.values)
            ChoiceChip(
              key: Key('language-${l.name}'),
              label: Text(l.nativeName),
              selected: l == current,
              showCheckmark: false,
              onSelected: (_) => LanguageController.instance.set(l),
            ),
        ],
      ),
    );
  }
}

/// Compact language button with a menu (login screen, captain app bar).
class LanguageMenuButton extends StatelessWidget {
  const LanguageMenuButton({super.key, this.compact = false});

  /// Icon only (narrow app bars).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = LanguageController.instance.value;
    return PopupMenuButton<AppLanguage>(
      key: const Key('language-menu'),
      tooltip: tr('Language'),
      initialValue: current,
      onSelected: LanguageController.instance.set,
      itemBuilder: (_) => [
        for (final l in AppLanguage.values)
          PopupMenuItem(
            value: l,
            child: Row(
              children: [
                SizedBox(width: 24, child: l == current ? const Icon(Icons.check_rounded, size: 18) : null),
                const SizedBox(width: Space.sm),
                Text(l.nativeName),
                if (l != AppLanguage.en) ...[const SizedBox(width: Space.sm), Text('· ${l.englishName}', style: const TextStyle(fontSize: 12))],
              ],
            ),
          ),
      ],
      child: compact
          ? const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.translate_rounded))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(current.nativeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
    );
  }
}
