// Renders every main Manager/Captain screen with realistic sample data at
// phone, tablet and desktop sizes (light + dark) and fails on any layout
// overflow or exception.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/layout/app_shell.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/customers/customers_screen.dart';
import 'package:pos_app/features/kitchen/kitchen_screen.dart';
import 'package:pos_app/features/manager/manager_home_screen.dart';
import 'package:pos_app/features/menu/menu_management_screen.dart';
import 'package:pos_app/features/menu/menu_models.dart';
import 'package:pos_app/features/orders/order_details_sheet.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/orders/order_service.dart';
import 'package:pos_app/features/orders/orders_board_screen.dart';
import 'package:pos_app/features/orders/settle_bill_sheet.dart';
import 'package:pos_app/features/pos/pos_screen.dart';
import 'package:pos_app/features/reports/reports_screen.dart';
import 'package:pos_app/features/settings/business_settings.dart';
import 'package:pos_app/features/settings/settings_screen.dart';

const sizes = {
  'small phone': Size(360, 740),
  'phone': Size(390, 844),
  'tablet': Size(820, 1180),
  'desktop': Size(1440, 900),
};

final now = DateTime.now();
Timestamp ago(int minutes) => Timestamp.fromDate(now.subtract(Duration(minutes: minutes)));

final settings = BusinessSettings({
  'shopName': 'Pizza La Forno',
  'showGst': true,
  'gstPercentage': '5',
  'numberOfTables': 12,
  'defaultOrderType': 'Dine-In',
});

MenuData menu() {
  const sizesClassic = [MenuVariant(label: '8 inch', price: 240, note: '6 pcs'), MenuVariant(label: '10 inch', price: 300, note: '6 pcs')];
  const burst = [MenuAddOn(name: 'Cheese burst-style', price: 120, variantLabels: ['10 inch'])];
  return MenuData(
    categories: const [
      MenuCategory(id: 'g', name: 'Garlic Bread', sortOrder: 1),
      MenuCategory(id: 'p', name: 'Pizza', sortOrder: 2),
      MenuCategory(id: 'b', name: 'Beverages', sortOrder: 3),
    ],
    subcategories: const [
      MenuSubcategory(id: 'c', categoryId: 'p', name: 'Classic', sortOrder: 1),
      MenuSubcategory(id: 'n', categoryId: 'p', name: 'Neapolitan Pizza', sortOrder: 2),
    ],
    items: const [
      MenuItem(id: '1', categoryId: 'p', subcategoryId: 'c', name: 'Margherita', description: 'Tomato sauce, mozzarella and fresh basil', variants: sizesClassic, addOns: burst),
      MenuItem(id: '2', categoryId: 'p', subcategoryId: 'c', name: 'Chili Cheese Corn', description: 'Sweet Corn , Paprika Spice', variants: sizesClassic, addOns: burst, spicyLevel: 1),
      MenuItem(id: '3', categoryId: 'p', subcategoryId: 'n', name: 'Seven Cheese Wonder', isJain: true, variants: [MenuVariant(label: '12 inch', price: 650)]),
      MenuItem(id: '4', categoryId: 'g', name: 'Paneer ,Red Peprika & Chilly Thecha', variants: [MenuVariant(label: 'Open', price: 260), MenuVariant(label: 'Stuffed', price: 260)], isAvailable: false),
      MenuItem(id: '5', categoryId: 'b', name: 'Thums Up', variants: [MenuVariant(label: 'Standard', price: 20)]),
    ],
  );
}

List<PosOrder> orders() => [
      PosOrder('ORD000001', {
        'customerName': 'Rahul Sharma (Table 4)',
        'tableNo': 'Table 4',
        'customerPhone': '9825012345',
        'status': 'preparing',
        'paymentStatus': 'pending',
        'totalPrice': 1176.0,
        'subtotal': 1120.0,
        'hasGst': true,
        'gstPercentage': 5.0,
        'specialRequest': 'Less spicy, Jain for one pizza please',
        'hasNewItemsAdded': true,
        'items': [
          {'name': 'Margherita + Cheese burst-style', 'size': '10 inch', 'price': 420.0, 'qty': 2, 'isDone': false},
          {'name': 'Paneer ,Red Peprika & Chilly Thecha', 'size': 'Stuffed', 'price': 260.0, 'qty': 1, 'isDone': true},
          {'name': 'Thums Up', 'size': 'Standard', 'price': 20.0, 'qty': 1},
        ],
        'createdAt': ago(25),
      }),
      PosOrder('ORD000002', {
        'customerName': 'Sharma Tea Stall Very Long Name',
        'tableNo': 'Sharma Tea Stall Very Long Name',
        'status': 'pending',
        'paymentStatus': 'pending',
        'totalPrice': 300.0,
        'items': [
          {'name': 'Margherita', 'size': '10 inch', 'price': 300.0, 'qty': 1},
        ],
        'createdAt': ago(3),
      }),
      PosOrder('ORD000003', {
        'customerName': 'Table 9',
        'tableNo': '9',
        'status': 'ready',
        'paymentStatus': 'paid_upi',
        'totalPrice': 650.0,
        'items': [
          {'name': 'Seven Cheese Wonder', 'size': '12 inch', 'price': 650.0, 'qty': 1},
        ],
        'createdAt': ago(40),
      }),
      PosOrder('ORD000004', {
        'customerName': 'Priya',
        'customerPhone': '9000011111',
        'tableNo': '2',
        'status': 'completed',
        'paymentStatus': 'paid_cash',
        'totalPrice': 520.0,
        'discountGiven': 20.0,
        'items': [
          {'name': 'Chili Cheese Corn', 'size': '8 inch', 'price': 240.0, 'qty': 2},
        ],
        'createdAt': ago(120),
        'completedAt': ago(90),
      }),
    ];

Future<void> pumpAt(WidgetTester t, Size size, Widget child, ThemeData theme) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: child)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void checkScreen(String name, Widget Function() build) {
  for (final theme in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
    for (final s in sizes.entries) {
      testWidgets('$name · ${s.key} · ${theme.key}', (t) async {
        await pumpAt(t, s.value, build(), theme.value);
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// Load the real Inter font so text is measured like in the app.
Future<void> loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(loadInter);

  checkScreen('POS', () => PosScreen(menuStream: Stream.value(menu()), settingsStream: Stream.value(settings)));
  checkScreen('Tables', () => OrdersBoardScreen(canDelete: true, ordersStream: Stream.value(orders()), settingsStream: Stream.value(settings)));
  checkScreen('Kitchen', () => KitchenScreen(ordersStream: Stream.value(orders())));
  checkScreen(
    'Dashboard',
    () => ManagerHomeScreen(
      onNewOrder: () {},
      onOpenTables: () {},
      ordersStream: Stream.value(orders()),
      settingsStream: Stream.value(settings),
    ),
  );
  checkScreen('Reports', () => ReportsScreen(ordersStream: Stream.value(orders())));
  checkScreen('Customers', () => CustomersScreen(ordersStream: Stream.value(orders())));
  checkScreen('Menu management', () => MenuManagementScreen(cafeId: 'test', menuStream: Stream.value(menu())));
  checkScreen('Settings', () => SettingsScreen(loader: () async => settings));

  for (final s in sizes.entries) {
    testWidgets('AppShell with 10 sections · ${s.key}', (t) async {
      await pumpAt(
        t,
        s.value,
        AppShell(
          brandTitle: 'Pizza La Forno',
          brandSubtitle: 'Manager',
          destinations: [
            for (var i = 0; i < 10; i++)
              ShellDestination(icon: Icons.circle_outlined, label: 'Section $i', onMobileBar: i < 4, badge: i == 2 ? 5 : null, section: i == 4 ? 'Manage' : null),
          ],
          selectedIndex: 2,
          onSelect: (_) {},
          onLogout: () {},
          body: const Center(child: Text('body')),
        ),
        AppTheme.light(),
      );
      expect(t.takeException(), isNull);
      expect(find.text('Section 2'), findsWidgets);
    });

    testWidgets('Manager bottom navigation · ${s.key}', (t) async {
      var selected = 2;
      await pumpAt(
        t,
        s.value,
        StatefulBuilder(
          builder: (ctx, set) => AppShell(
            bottomNav: true,
            brandTitle: 'Pizza La Forno',
            brandSubtitle: 'Manager',
            destinations: [
              for (final l in ['Dashboard', 'Tables', 'Kitchen', 'Menu', 'Reports', 'Customers', 'Staff', 'Settings'])
                ShellDestination(icon: Icons.circle_outlined, label: l, onMobileBar: ['Dashboard', 'Tables', 'Kitchen', 'Menu'].contains(l), badge: l == 'Tables' ? 3 : null),
            ],
            selectedIndex: selected,
            onSelect: (i) => set(() => selected = i),
            onLogout: () {},
            body: const Center(child: Text('body')),
          ),
        ),
        AppTheme.light(),
      );
      expect(t.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      final slots = (s.value.width / 96).floor().clamp(5, 12);
      if (8 <= slots) {
        expect(find.text('Settings'), findsOneWidget, reason: 'all sections fit');
        expect(find.text('More'), findsNothing);
      } else {
        expect(find.text('More'), findsOneWidget);
        await t.tap(find.text('More'));
        await t.pumpAndSettle();
        expect(find.text('Sign out'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('Settle bill sheet · ${s.key}', (t) async {
      await pumpAt(
        t,
        s.value,
        Builder(builder: (ctx) => TextButton(onPressed: () => showSettleBillSheet(ctx, orders().first, settings), child: const Text('open'))),
        AppTheme.light(),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Settle bill'), findsOneWidget);
      // Choose a % discount and cash: totals must update without overflow.
      await t.tap(find.text('%'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '10');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('Order details sheet · ${s.key}', (t) async {
      await pumpAt(
        t,
        s.value,
        Builder(builder: (ctx) => TextButton(onPressed: () => showOrderDetailsSheet(ctx, orders().first, settings, canDelete: true), child: const Text('open'))),
        AppTheme.light(),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Settle bill'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('POS phone: add items then open the cart sheet', (t) async {
    await pumpAt(t, sizes['phone']!, PosScreen(menuStream: Stream.value(menu()), settingsStream: Stream.value(settings)), AppTheme.light());
    await t.tap(find.text('Add').last); // Thums Up (single size → added directly)
    await t.pumpAndSettle();
    expect(find.text('View order'), findsOneWidget);
    await t.tap(find.text('View order'));
    await t.pumpAndSettle();
    expect(find.text('Send to kitchen'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('POS: phone lookup fills, replaces and clears the customer name', (t) async {
    final known = {
      '6353268656': KnownCustomer('Sahil', const [], DateTime(2026, 11, 1)),
      '6353268655': KnownCustomer('Sahil 2', const [], DateTime(2026, 11, 1)),
    };
    await pumpAt(
      t,
      sizes['desktop']!,
      PosScreen(
        menuStream: Stream.value(menu()),
        settingsStream: Stream.value(settings),
        customerLookup: (p) async => known[p],
      ),
      AppTheme.light(),
    );
    final phone = find.widgetWithText(TextField, 'Mobile');
    final name = find.widgetWithText(TextField, 'Customer name');
    String nameText() => (t.widget<TextField>(name)).controller!.text;

    await t.enterText(phone, '6353268656');
    await t.pumpAndSettle();
    expect(nameText(), 'Sahil');

    await t.enterText(phone, '635326865'); // deleting a digit clears the auto name
    await t.pumpAndSettle();
    expect(nameText(), '');

    await t.enterText(phone, '6353268655'); // other known customer → replaced
    await t.pumpAndSettle();
    expect(nameText(), 'Sahil 2');
    expect(find.textContaining('Welcome back, Sahil 2'), findsOneWidget);

    await t.enterText(phone, '6353268658'); // unknown number → blank
    await t.pumpAndSettle();
    expect(nameText(), '');
    expect(find.textContaining('Welcome back'), findsNothing);

    await t.enterText(name, 'Ravi'); // typed by hand → never overwritten
    await t.enterText(phone, '6353268656');
    await t.pumpAndSettle();
    expect(nameText(), 'Ravi');
    expect(t.takeException(), isNull);
  });

  testWidgets('POS desktop: size picker adds a line with add-on', (t) async {
    await pumpAt(t, sizes['desktop']!, PosScreen(menuStream: Stream.value(menu()), settingsStream: Stream.value(settings)), AppTheme.light());
    await t.tap(find.text('Margherita').first);
    await t.pumpAndSettle();
    await t.tap(find.text('10 inch'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cheese burst-style'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Add to order'));
    await t.pumpAndSettle();
    expect(find.text('Margherita + Cheese burst-style'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
