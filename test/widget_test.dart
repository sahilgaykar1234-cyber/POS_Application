// Foundation tests. These avoid Firebase (which needs platform setup) and
// check the pieces that the rest of the app now depends on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/core/theme/tokens.dart';
import 'package:pos_app/core/widgets/confirm_dialog.dart';

void main() {
  group('FirestorePaths tenant scoping', () {
    tearDown(() => FirestorePaths.setActiveCafe(null));

    test('no active cafe -> refuses instead of falling back to shared data', () {
      FirestorePaths.setActiveCafe(null);
      expect(() => FirestorePaths.activeCafeId, throwsStateError);
      FirestorePaths.setActiveCafe('');
      expect(() => FirestorePaths.activeCafeId, throwsStateError);
    });

    test('active cafe is the one set at sign-in', () {
      FirestorePaths.setActiveCafe('cafe123');
      expect(FirestorePaths.activeCafeId, 'cafe123');
    });

    test('legacy names documented for the migration', () {
      expect(FirestorePaths.legacyOrders, 'orders');
      expect(FirestorePaths.legacyMenuCategories, 'menu_categories');
      expect(FirestorePaths.legacySettingsDoc, 'settings/business_settings');
    });
  });

  test('light/dark themes carry the Ember palette', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.extension<Palette>(), Palette.light);
    expect(dark.extension<Palette>(), Palette.dark);
    expect(light.colorScheme.primary, const Color(0xFFC2410C));
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.textTheme.bodyMedium?.fontFamily, 'Inter');
  });

  test('Super Admin keeps its previous dark brown look', () {
    final t = AppTheme.legacyAdmin;
    expect(t.scaffoldBackgroundColor, const Color(0xFF141211));
    expect(t.colorScheme.primary, const Color(0xFFE65C00));
  });

  group('showDangerConfirmDialog', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
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

    FilledButton confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Reset Menu'),
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
        theme: AppTheme.light(),
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
