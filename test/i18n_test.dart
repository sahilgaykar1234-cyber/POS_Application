// Language switching: every main screen renders in Hindi, Gujarati and
// Marathi at phone and desktop sizes without overflow, and no fixed English
// text is left on screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/i18n/language_picker.dart';
import 'package:pos_app/core/i18n/tr.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/customers/customers_screen.dart';
import 'package:pos_app/features/kitchen/kitchen_screen.dart';
import 'package:pos_app/features/manager/manager_home_screen.dart';
import 'package:pos_app/features/menu/menu_management_screen.dart';
import 'package:pos_app/features/orders/orders_board_screen.dart';
import 'package:pos_app/features/orders/orders_screen.dart';
import 'package:pos_app/features/pos/pos_screen.dart';
import 'package:pos_app/features/receipt/bill_view.dart';
import 'package:pos_app/features/reports/reports_screen.dart';
import 'package:pos_app/features/settings/settings_screen.dart';
import 'package:pos_app/features/takeaway/takeaway_screen.dart';

import 'layout_test.dart' show menu, orders, takeawayOrders, settings, pumpAt, loadInter;

Future<void> loadIndicFonts() async {
  for (final family in ['NotoSansDevanagari', 'NotoSansGujarati']) {
    final loader = FontLoader(family);
    for (final w in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
    }
    await loader.load();
  }
}

/// Words that are names/data or the same in every language.
final _allowed = RegExp(
  r'^(Pizza La Forno|Margherita.*|Paneer.*|Chili Cheese Corn|Seven Cheese Wonder|Thums Up|Garlic Bread|Pizza|Beverages|Classic|'
  r'Neapolitan Pizza|Paneer ,Red Peprika & Chilly Thecha|Cheese burst-style|Rahul.*|Priya.*|Anita Desai|Vikram|Sonal|'
  r'Sharma Tea Stall.*|Tomato sauce.*|Sweet Corn.*|Less spicy.*|Extra napkins|Open|Stuffed|Standard|GST.*|UPI.*|PIN.*|'
  r'CSV.*|WhatsApp.*|POS.*|A4.*|USB.*|Chrome.*|PNG.*|English|Hindi|Gujarati|Marathi|Walk-in|Cafe POS|My Cafe|INR|'
  r'.*inch.*|.*pcs.*|T\d+|V-\d+|J|#.*|ORD.*|TKW.*|Table \d+.*|e\.g\..*|\d.*)$',
);

List<String> englishLeft(WidgetTester t) {
  final out = <String>{};
  for (final e in find.byWidgetPredicate((w) => w is Text || w is RichText).evaluate()) {
    final w = e.widget;
    final s = w is Text ? (w.data ?? w.textSpan?.toPlainText() ?? '') : (w as RichText).text.toPlainText();
    for (final part in s.split(RegExp(r'\s*[·\n]\s*'))) {
      final p = part.trim();
      if (!RegExp(r'[A-Za-z]{3,}').hasMatch(p) || _allowed.hasMatch(p)) continue;
      if (RegExp(r'[\u0900-\u0AFF]').hasMatch(p)) continue; // translated, maybe with a name inside
      if (p == p.toUpperCase() || p.contains('₹')) continue; // category headers / prices of menu data
      if (RegExp(r'^\d{1,2} [A-Z][a-z]{2}( \d{4})?').hasMatch(p)) continue; // dates
      out.add(p);
    }
  }
  return out.toList()..sort();
}

void main() {
  setUpAll(() async {
    await loadInter();
    await loadIndicFonts();
  });
  tearDown(() => LanguageController.instance.value = AppLanguage.en);

  group('tr()', () {
    test('English is the default and the fallback', () {
      LanguageController.instance.value = AppLanguage.en;
      expect(tr('Tables'), 'Tables');
      LanguageController.instance.value = AppLanguage.hi;
      expect(tr('Some text with no translation'), 'Some text with no translation');
    });

    test('translates and fills placeholders', () {
      LanguageController.instance.value = AppLanguage.hi;
      expect(tr('Tables'), 'टेबल');
      expect(tr('Table {0}', ['4']), 'टेबल 4');
      LanguageController.instance.value = AppLanguage.gu;
      expect(tr('Send to kitchen'), 'કિચનમાં મોકલો');
      LanguageController.instance.value = AppLanguage.mr;
      expect(tr('{0} min ago', [5]), '5 मिनिटांपूर्वी');
    });

    test('enum labels follow the language', () {
      LanguageController.instance.value = AppLanguage.hi;
      expect(tr('Today'), 'आज');
    });
  });

  testWidgets('choosing a language in Settings changes the screen at once', (t) async {
    await pumpAt(t, const Size(1440, 900), SettingsScreen(loader: () async => settings), AppTheme.light());
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    await t.ensureVisible(find.byKey(const Key('language-hi')));
    await t.tap(find.byKey(const Key('language-hi')));
    await t.pumpAndSettle();
    expect(LanguageController.instance.value, AppLanguage.hi);
    expect(find.text('सेटिंग्स'), findsWidgets);
    expect(find.text('Settings'), findsNothing);
    await t.tap(find.byKey(const Key('language-en')));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('language menu button switches language', (t) async {
    await pumpAt(t, const Size(800, 600), const Center(child: LanguageMenuButton()), AppTheme.light());
    await t.tap(find.byKey(const Key('language-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('ગુજરાતી').last);
    await t.pumpAndSettle();
    expect(LanguageController.instance.value, AppLanguage.gu);
  });

  final screens = <String, Widget Function()>{
    'Dashboard': () => ManagerHomeScreen(onNewOrder: () {}, onOpenTables: () {}, ordersStream: Stream.value(orders()), settingsStream: Stream.value(settings)),
    'Tables': () => OrdersBoardScreen(canDelete: true, ordersStream: Stream.value(orders()), settingsStream: Stream.value(settings)),
    'POS': () => PosScreen(menuStream: Stream.value(menu()), settingsStream: Stream.value(settings)),
    'Takeaway': () => TakeawayScreen(ordersStream: Stream.value([...orders(), ...takeawayOrders()]), settingsStream: Stream.value(settings)),
    'Orders': () => OrdersScreen(ordersStream: Stream.value([...orders(), ...takeawayOrders()]), settingsStream: Stream.value(settings)),
    'Kitchen': () => KitchenScreen(ordersStream: Stream.value(orders())),
    'Menu': () => MenuManagementScreen(cafeId: 'test', menuStream: Stream.value(menu())),
    'Reports': () => ReportsScreen(ordersStream: Stream.value(orders())),
    'Customers': () => CustomersScreen(ordersStream: Stream.value(orders())),
    'Settings': () => SettingsScreen(loader: () async => settings),
    'Bill': () => BillView(order: orders()[3].data, orderId: 'ORD000004', settings: settings.receiptSettings, mode: BillMode.paymentSuccess),
  };

  for (final lang in [AppLanguage.hi, AppLanguage.gu, AppLanguage.mr]) {
    for (final size in {'phone': const Size(360, 740), 'desktop': const Size(1440, 900)}.entries) {
      for (final s in screens.entries) {
        testWidgets('${s.key} in ${lang.englishName} · ${size.key}', (t) async {
          LanguageController.instance.value = lang;
          await pumpAt(t, size.value, s.value(), AppTheme.light());
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          // The bill preview is the customer receipt: it stays in English.
          final left = s.key == 'Bill' ? const <String>[] : englishLeft(t);
          expect(left, isEmpty, reason: 'English text left on ${s.key}: $left');
        });
      }
    }
  }
}
