import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/core/utils/friendly_error.dart';
import 'package:pos_app/features/admin/admin_data.dart';
import 'package:pos_app/features/admin/admin_service.dart';
import 'package:pos_app/features/admin/cafe_detail_screen.dart';

import 'admin_test.dart' as at;
import 'layout_test.dart' as lt;

void main() {
  test('Firebase errors become plain sentences (no codes, no links)', () {
    final index = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'failed-precondition',
      message: 'The query requires an index. You can create it here: https://console.firebase.google.com/...',
    );
    final msg = friendlyError(index, 'load the summary');
    expect(msg, 'Could not load the summary. This isn\'t set up on the server yet. Please try again later.');
    expect(msg, isNot(contains('http')));
    expect(msg, isNot(contains('failed-precondition')));
    expect(friendlyError(FirebaseException(plugin: 'x', code: 'permission-denied')), 'You don\'t have permission to do this.');
    expect(friendlyError(FirebaseException(plugin: 'x', code: 'unavailable')), contains('internet'));
    expect(friendlyError(Exception('weird stack trace')), 'Something went wrong. Please try again.');
    expect(friendlyPrintError(Exception('NotFoundError: No device selected.')), 'No printer was selected.');
  });

  testWidgets('Menu & sales: a missing number shows "—", never an error page', (t) async {
    await lt.loadInter();
    await lt.pumpAt(
      t,
      lt.sizes['desktop']!,
      CafeDetailScreen(
        cafeId: 'flammy',
        data: AdminDataController.fixed(at.sampleData()),
        settingsStream: Stream.value(const {'dayEndsAt': '05:00'}),
        auditStream: Stream.value(const []),
        historyStream: Stream.value(const []),
        ops: Future.value(const CafeOpsSummary(categories: 9, menuItems: 56, availableItems: 54, ordersToday: 3, orders30d: 40, billed30d: null, lastOrderAt: null)),
      ),
      AppTheme.light(),
    );
    await t.tap(find.text('Menu & sales'));
    await t.pumpAndSettle();
    expect(find.text('Billed, last 30 days'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Something went wrong'), findsNothing);
    expect(find.textContaining('FirebaseError'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
