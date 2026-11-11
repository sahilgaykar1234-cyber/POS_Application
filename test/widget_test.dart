// Foundation tests. These avoid Firebase (which needs platform setup) and
// check the pieces that the rest of the app now depends on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/core/widgets/confirm_dialog.dart';

void main() {
  test('legacy Firestore paths are unchanged (must match live data)', () {
    expect(FirestorePaths.ordersCollection, 'orders');
    expect(FirestorePaths.menuCategoriesCollection, 'menu_categories');
    expect(FirestorePaths.settingsCollection, 'settings');
    expect(FirestorePaths.businessSettingsDocId, 'business_settings');
  });

  test('AppTheme keeps the original brand colours', () {
    final theme = AppTheme.dark;
    expect(theme.scaffoldBackgroundColor, const Color(0xFF141211));
    expect(theme.colorScheme.primary, const Color(0xFFE65C00));
    expect(theme.colorScheme.secondary, const Color(0xFFF7B731));
  });

  group('showDangerConfirmDialog', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await showDangerConfirmDialog(
                context,
                title: 'Reset',
                message: 'Danger',
                confirmLabel: 'Reset Menu',
                confirmText: 'RESET',
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    ElevatedButton confirmButton(WidgetTester tester) => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Reset Menu'),
        );

    testWidgets('confirm is disabled until the exact text is typed', (tester) async {
      await openDialog(tester);
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'reset'); // wrong case
      await tester.pump();
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'RESET');
      await tester.pump();
      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDangerConfirmDialog(
                context,
                title: 'Reset',
                message: 'Danger',
                confirmLabel: 'Reset Menu',
                confirmText: 'RESET',
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
