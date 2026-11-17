import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/auth/login_screen.dart';

import 'layout_test.dart' as lt;

void main() {
  setUpAll(lt.loadInter);

  for (final s in lt.sizes.entries) {
    testWidgets('login: "See how it works" opens the product film, never autoplays · ${s.key}', (t) async {
      await lt.pumpAt(t, s.value, const LoginScreen(), AppTheme.light());
      expect(find.byKey(const Key('product-video')), findsOneWidget);
      expect(find.text('Cafe POS in 1:44'), findsNothing, reason: 'nothing plays until tapped');

      await t.ensureVisible(find.byKey(const Key('product-video')));
      await t.tap(find.byKey(const Key('product-video')));
      await t.pumpAndSettle();
      expect(find.text('Cafe POS in 1:44'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.byKey(const Key('product-video-close')));
      await t.pumpAndSettle();
      expect(find.text('Cafe POS in 1:44'), findsNothing);
    });
  }
}
