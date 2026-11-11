import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/features/customers/customers_screen.dart';
import 'package:pos_app/features/manager/sales_stats.dart';
import 'package:pos_app/features/menu/menu_models.dart';
import 'package:pos_app/features/orders/bill.dart';
import 'package:pos_app/features/orders/bill_numbers.dart';
import 'package:pos_app/features/orders/custom_item_dialog.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/orders/order_service.dart';
import 'package:pos_app/features/orders/orders_board_screen.dart';
import 'package:pos_app/features/orders/whatsapp_bill.dart';
import 'package:pos_app/features/takeaway/takeaway_board.dart';
import 'package:flutter/material.dart';
import 'package:pos_app/features/pos/pos_cart.dart';
import 'package:pos_app/features/reports/reports_csv.dart';

PosOrder order(String id, Map<String, dynamic> d) => PosOrder(id, d);
Timestamp ts(DateTime d) => Timestamp.fromDate(d);

void main() {
  group('Bill (billing maths must not change)', () {
    final items = [
      {'name': 'Simply Margerita', 'price': 130.0, 'qty': 2},
      {'name': 'Cold Coffee', 'price': 80.0, 'qty': 1},
    ];

    /// The original app's formula, copied verbatim.
    double oldTotal(List<Map<String, dynamic>> items, bool showGst, double gstPercent) {
      double subtotal = 0;
      for (final item in items) {
        subtotal += ((item['price'] ?? 0.0) * (item['qty'] ?? 1));
      }
      if (showGst) return subtotal + subtotal * (gstPercent / 100.0);
      return subtotal;
    }

    test('without discount: identical to the old formula', () {
      for (final gst in [false, true]) {
        for (final pct in [0.0, 5.0, 12.0, 18.0]) {
          final b = Bill.compute(items: items, gstEnabled: gst, gstPercent: pct);
          expect(b.total, oldTotal(items, gst, pct), reason: 'gst=$gst pct=$pct');
          expect(b.subtotal, 340);
          expect(b.discount, 0);
        }
      }
    });

    test('percent discount comes off before GST', () {
      final b = Bill.compute(items: items, gstEnabled: true, gstPercent: 5, discountType: DiscountType.percent, discountValue: 10);
      expect(b.discount, 34);
      expect(b.gst, closeTo(15.3, 1e-9));
      expect(b.total, closeTo(321.3, 1e-9));
    });

    test('amount discount is capped at the subtotal', () {
      final b = Bill.compute(items: items, gstEnabled: false, gstPercent: 5, discountType: DiscountType.amount, discountValue: 9999);
      expect(b.discount, 340);
      expect(b.total, 0);
    });

    test('payment status format stays compatible with receipts/reports', () {
      expect(PaymentMethod.cash.status, 'paid_cash');
      expect(PaymentMethod.upi.status, 'paid_upi');
      expect(PaymentMethod.card.status, 'paid_card');
      expect(methodFromStatus('paid_upi'), PaymentMethod.upi);
      expect(isPaidStatus('pending'), isFalse);
      expect(isPaidStatus('paid_cash'), isTrue);
    });
  });

  group('TableBoard (original table matching rules)', () {
    final now = DateTime.now();
    final orders = [
      order('a', {'tableNo': '3', 'status': 'pending', 'createdAt': ts(now)}),
      order('b', {'tableNo': 'Table 5', 'status': 'preparing', 'createdAt': ts(now)}),
      order('c', {'customerName': 'Rahul (Table 7)', 'status': 'ready', 'createdAt': ts(now)}),
      order('d', {'tableNo': 'V-12', 'status': 'pending', 'createdAt': ts(now)}),
      order('e', {'tableNo': 'Sharma Tea', 'status': 'pending', 'createdAt': ts(now)}),
      order('f', {'tableNo': '2', 'status': 'completed', 'createdAt': ts(now)}),
      order('g', {'tableNo': '', 'status': 'pending', 'createdAt': ts(now)}),
    ];

    test('places orders on numbered and virtual tables', () {
      final board = TableBoard.build(orders, 12);
      expect(board.byTable.keys.toSet(), {3, 5, 7});
      expect(board.virtuals.map((o) => o.id).toSet(), {'d', 'e'});
      expect(board.byTable.containsKey(2), isFalse, reason: 'completed frees the table');
    });

    test('tables beyond the configured count become virtual', () {
      final board = TableBoard.build(orders, 4);
      expect(board.byTable.keys.toSet(), {3});
      expect(board.virtuals.map((o) => o.id).toSet(), {'b', 'd', 'e'});
    });
  });

  group('display name & customer input (original rules)', () {
    test('formatCustomerDisplayName', () {
      expect(formatCustomerDisplayName('Rahul', '4'), 'Rahul (Table 4)');
      expect(formatCustomerDisplayName('Rahul (Table 4)', 'Table 4'), 'Rahul (Table 4)');
      expect(formatCustomerDisplayName('', '4'), 'Table 4');
      expect(formatCustomerDisplayName('', null), 'Counter Customer');
    });

    test('name and phone typed in the wrong boxes are swapped', () {
      final c = CustomerInput.normalize('9825012345', 'Rahul');
      expect(c.name, 'Rahul');
      expect(c.phone, '9825012345');
      final d = CustomerInput.normalize('Rahul', '98250-12345');
      expect(d.phone, '9825012345');
    });
  });

  group('PosCart', () {
    const pizza = MenuItem(
      id: 'm',
      categoryId: 'c',
      name: 'Margherita',
      variants: [MenuVariant(label: '8 inch', price: 240), MenuVariant(label: '10 inch', price: 300)],
      addOns: [MenuAddOn(name: 'Cheese burst-style', price: 120, variantLabels: ['10 inch'])],
    );

    test('same name+size merges, qty counts across variants and add-ons', () {
      final cart = PosCart();
      cart.add(CartLine.build(pizza, pizza.variants[0], const []));
      cart.add(CartLine.build(pizza, pizza.variants[0], const []));
      cart.add(CartLine.build(pizza, pizza.variants[1], pizza.addOns));
      expect(cart.lines.length, 2);
      expect(cart.lines[0]['qty'], 2);
      expect(cart.lines[1]['name'], 'Margherita + Cheese burst-style');
      expect(cart.lines[1]['price'], 420);
      expect(cart.qtyOfItem('Margherita'), 3);
      expect(cart.bill(gstEnabled: false, gstPercent: 5).total, 900);
    });

    test('qty 0 removes the line', () {
      final cart = PosCart()..add(CartLine.build(pizza, pizza.variants[0], const []));
      cart.setQty(0, 0);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('SalesStats', () {
    final now = DateTime(2026, 11, 11, 20);
    final orders = [
      order('1', {'status': 'completed', 'paymentStatus': 'paid_cash', 'totalPrice': 100, 'createdAt': ts(DateTime(2026, 11, 11, 13)), 'items': [{'name': 'A', 'qty': 2, 'price': 50}]}),
      order('2', {'status': 'completed', 'paymentStatus': 'paid_upi', 'totalPrice': 200, 'createdAt': ts(DateTime(2026, 11, 11, 19)), 'items': [{'name': 'B + Cheese', 'qty': 1, 'price': 200}]}),
      order('3', {'status': 'completed', 'paymentStatus': 'paid_card', 'totalPrice': 50, 'createdAt': ts(DateTime(2026, 11, 11, 19)), 'items': [{'name': 'B', 'qty': 1, 'price': 50}]}),
      order('4', {'status': 'pending', 'paymentStatus': 'pending', 'totalPrice': 70, 'createdAt': ts(DateTime(2026, 11, 11, 19)), 'items': [{'name': 'A', 'qty': 1, 'price': 70}]}),
      order('5', {'status': 'cancelled', 'paymentStatus': 'pending', 'totalPrice': 999, 'createdAt': ts(DateTime(2026, 11, 11, 18))}),
    ];

    test('sales = paid bills of every method; counts by status', () {
      final s = SalesStats.of(orders);
      expect(s.sales, 350);
      expect(s.byMethod[PaymentMethod.cash], 100);
      expect(s.byMethod[PaymentMethod.upi], 200);
      expect(s.byMethod[PaymentMethod.card], 50);
      expect(s.running, 1);
      expect(s.completed, 3);
      expect(s.cancelled, 1);
      expect(s.unpaid, 1);
      expect(s.byHour[19], 250);
      expect(s.topItems.first, ('A', 3));
      expect(s.topItems[1], ('B', 2), reason: 'add-ons fold into the base item');
    });

    test('daily series', () {
      final d = SalesStats.dailySales(orders, days: 2, now: now);
      expect(d.length, 2);
      expect(d.last.$2, 350);
      expect(d.first.$2, 0);
    });
  });

  group('customers & CSV', () {
    final o = [
      order('abcdef1', {'status': 'completed', 'customerName': 'Rahul (Table 4)', 'customerPhone': '9825012345', 'totalPrice': 100, 'createdAt': ts(DateTime(2026, 11, 10, 12))}),
      order('abcdef2', {'status': 'completed', 'customerName': 'Rahul', 'customerPhone': '9825012345', 'totalPrice': 60, 'createdAt': ts(DateTime(2026, 11, 11, 12)), 'items': [{'name': 'X', 'qty': 1, 'price': 60}]}),
      order('abcdef3', {'status': 'pending', 'customerName': 'Sonal', 'customerPhone': '9000000000', 'totalPrice': 10, 'createdAt': ts(DateTime(2026, 11, 11, 13))}),
    ];

    test('directory aggregates completed orders by phone', () {
      final c = buildCustomers(o);
      expect(c.length, 1);
      expect(c.first.orders, 2);
      expect(c.first.spent, 160);
      expect(c.first.lastOrder.id, 'abcdef2');
    });

    test('sales CSV keeps the original columns', () {
      final csv = salesCsv(o, DateTime(2026, 11, 1), DateTime(2026, 11, 30));
      final lines = csv.trim().split('\n');
      expect(lines.first, 'Bill No,Date,Time,Table No,Customer Name,Phone,Item Count,Subtotal,GST,Discount,Grand Total,Payment Status,Order Status');
      expect(lines.length, 4);
      expect(lines[1], startsWith('"#ABCDE"'));
    });
  });

  group('Table timer', () {
    test('format', () {
      expect(formatElapsed(const Duration(seconds: 45)), '0:45');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
      expect(formatElapsed(const Duration(seconds: -3)), '0:00');
    });

    testWidgets('runs until paid, then stops', (t) async {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TableTimer(start: start))));
      final first = (t.widget<Text>(find.byType(Text))).data!;
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100))); // real time passes
      await t.pump(const Duration(seconds: 1)); // timer tick
      final later = (t.widget<Text>(find.byType(Text))).data!;
      expect(first, startsWith('5:'));
      expect(later, isNot(first), reason: 'keeps ticking while unpaid');
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: TableTimer(start: start, stoppedAt: start.add(const Duration(minutes: 7, seconds: 30)))),
      ));
      expect(find.text('7:30'), findsOneWidget, reason: 'frozen at payment time');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });

  group('WhatsApp bill', () {
    test('numbers', () {
      expect(normalizeWhatsAppNumber('98250 12345'), '919825012345');
      expect(normalizeWhatsAppNumber('09825012345'), '919825012345');
      expect(normalizeWhatsAppNumber('+91 98250 12345'), '919825012345');
      expect(normalizeWhatsAppNumber('12345'), isNull);
      expect(normalizeWhatsAppNumber(''), isNull);
    });

    test('bill text has items, discount, GST, total and payment', () {
      final text = buildWhatsAppBill(
        orderId: 'abcdef123',
        settings: {'shopName': 'Pizza La Forno', 'thankYouMessage': 'Visit again!'},
        order: {
          'tableNo': '4',
          'items': [
            {'name': 'Margherita + Cheese burst-style', 'size': '10 inch', 'price': 420, 'qty': 2},
            {'name': 'Thums Up', 'size': 'Standard', 'price': 20, 'qty': 1},
          ],
          'subtotal': 860,
          'discountGiven': 86,
          'hasGst': true,
          'gstPercentage': 5,
          'totalPrice': 812.7,
          'paymentStatus': 'paid_upi',
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 11, 20, 5)),
        },
      );
      expect(text, contains('*Pizza La Forno*'));
      expect(text, contains('Bill #ABCDEF · 11/11/2026 20:05'));
      expect(text, contains('Table 4'));
      expect(text, contains('2 × Margherita + Cheese burst-style (10 inch) — ₹840'));
      expect(text, contains('1 × Thums Up — ₹20'));
      expect(text, contains('Discount: -₹86'));
      expect(text, contains('GST 5%: ₹38.70'));
      expect(text, contains('*Total: ₹812.70*'));
      expect(text, contains('Paid via UPI'));
      expect(text, endsWith('Visit again!'));
      final web = whatsAppDirectUri('919825012345', text, mobile: false);
      expect(web.host, 'web.whatsapp.com');
      expect(web.queryParameters['phone'], '919825012345');
      expect(web.queryParameters['text'], text);
      final app = whatsAppDirectUri('919825012345', text, mobile: true);
      expect(app.scheme, 'whatsapp');
      expect(app.queryParameters['text'], text);
      final uri = whatsAppUri('919825012345', text);
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919825012345');
      expect(uri.queryParameters['text'], text);
    });
  });

  group('Takeaway', () {
    final now = DateTime(2026, 11, 11, 20, 0);
    PosOrder t(String id, int? token, String status, {int? pickupIn, String table = '', String type = 'Takeaway', bool paid = false}) => PosOrder(id, {
          'orderType': type,
          'tableNo': table,
          'tokenNo': ?token,
          'status': status,
          'customerName': 'Rahul',
          'paymentStatus': paid ? 'paid_cash' : 'pending',
          'createdAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 10))),
          if (pickupIn != null) 'pickupAt': Timestamp.fromDate(now.add(Duration(minutes: pickupIn))),
        });

    test('board groups by status and sorts by token; dine-in excluded', () {
      final b = TakeawayBoard.from([
        t('a', 3, 'pending'),
        t('b', 1, 'pending'),
        t('c', 2, 'preparing'),
        t('d', 4, 'ready', paid: true),
        t('e', 5, 'completed'),
        t('f', null, 'pending', type: 'Dine-In', table: '4'),
        t('g', 6, 'pending', table: 'Table 9'), // takeaway with a table → stays on Tables
      ]);
      expect(b.incoming.map((o) => o.tokenNo), [1, 3]);
      expect(b.preparing.map((o) => o.tokenNo), [2]);
      expect(b.ready.map((o) => o.tokenNo), [4]);
      expect(b.pickedUp.map((o) => o.tokenNo), [5]);
      expect(b.active, 4);
      expect(readyTokens(b), [4]);
    });

    test('takeaway orders never land on the Tables board', () {
      final board = TableBoard.build([t('x', 7, 'pending'), t('y', null, 'pending', type: 'Dine-In', table: '3')], 12);
      expect(board.byTable.keys, [3]);
      expect(board.virtuals, isEmpty);
    });

    test('pickup countdown', () {
      expect(pickupStatus(t('a', 1, 'pending'), now).state, PickupState.asap);
      expect(pickupStatus(t('a', 1, 'pending', pickupIn: 15), now).label, 'In 15 min');
      expect(pickupStatus(t('a', 1, 'pending', pickupIn: 4), now).state, PickupState.dueSoon);
      final late = pickupStatus(t('a', 1, 'preparing', pickupIn: -3), now);
      expect(late.state, PickupState.late);
      expect(late.label, 'Late by 3 min');
      expect(pickupStatus(t('a', 1, 'ready', pickupIn: -3), now).state, PickupState.onTime, reason: 'ready → waiting, not late');
    });

    test('labels and ready message', () {
      final o = t('abcdef1', 12, 'ready');
      expect(o.isTakeaway, isTrue);
      expect(o.tokenLabel, 'Token #12');
      expect(o.displayName, 'Rahul (Token #12)');
      expect(PosOrder('x', {'orderType': 'Takeaway', 'customerName': ''}).takeawayName, 'Walk-in');
      expect(
        buildReadyMessage(shopName: 'Pizza La Forno', customerName: 'Rahul', token: 12, billNo: '#ABC'),
        'Hi Rahul, your takeaway (Token #12) is *ready for pickup* at *Pizza La Forno*. See you soon!',
      );
      expect(takeawayDayKey(DateTime(2026, 3, 5)), '20260305');
    });
  });

  group('Bill number series', () {
    test('financial year flips on 1 April', () {
      expect(financialYear(DateTime(2026, 3, 31)), '2025-26');
      expect(financialYear(DateTime(2026, 4, 1)), '2026-27');
      expect(financialYear(DateTime(2099, 12, 31)), '2099-00');
      expect(financialYearShort(DateTime(2026, 11, 11)), '26-27');
      expect(billCounterName(DateTime(2027, 2, 1)), 'bills_2026-27');
    });

    test('format is FY/0001 and sorts in order', () {
      final now = DateTime(2026, 11, 11);
      expect(formatBillNumber(now, 1), '26-27/0001');
      expect(formatBillNumber(now, 42), '26-27/0042');
      expect(formatBillNumber(now, 12345), '26-27/12345');
      final list = [for (var i = 1; i <= 12; i++) formatBillNumber(now, i)];
      expect([...list]..sort(), list, reason: 'zero-padded so text order = number order');
    });

    test('stored number wins; old orders keep their id-based number', () {
      expect(displayBillNo({'billNo': '26-27/0042'}, 'abcdef123'), '26-27/0042');
      expect(displayBillNo({}, 'abcdef123'), '#ABCDEF');
      expect(displayBillNo({}, 'abcdef123', idChars: 5), '#ABCDE');
      expect(PosOrder('abcdef1', {'billNo': '26-27/0007'}).billNo, '26-27/0007');
      expect(PosOrder('abcdef1', {}).billNo, '#ABCDEF');
    });

    test('CSV and WhatsApp use the series number', () {
      final o = PosOrder('zzzzzz1', {
        'billNo': '26-27/0101',
        'status': 'completed',
        'totalPrice': 100,
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 11, 12)),
      });
      expect(salesCsv([o], DateTime(2026, 11, 1), DateTime(2026, 11, 30)), contains('"26-27/0101"'));
      expect(buildWhatsAppBill(order: o.data, orderId: o.id), contains('Bill 26-27/0101'));
    });
  });

  group('Next bill number follows the previous bill', () {
    test('no bills yet -> 0001 even if an old counter exists', () {
      expect(nextBillSeq(counterNext: null, counterLastOrderExists: false, lastSeqInOrders: 0), 1);
      expect(nextBillSeq(counterNext: 3, counterLastOrderExists: false, lastSeqInOrders: 0), 1);
    });
    test('continues after the latest bill', () {
      expect(nextBillSeq(counterNext: 8, counterLastOrderExists: true, lastSeqInOrders: 7), 8);
    });
    test('latest bill deleted -> reuse its number', () {
      expect(nextBillSeq(counterNext: 8, counterLastOrderExists: false, lastSeqInOrders: 6), 7);
    });
    test('never repeats a number a bill already has', () {
      expect(nextBillSeq(counterNext: 3, counterLastOrderExists: true, lastSeqInOrders: 9), 10);
    });
    test('billKey sorts across years and restarts on 1 April', () {
      expect(billKey(DateTime(2026, 11, 11), 42), 202600042);
      expect(seqInYear(202600042, DateTime(2027, 3, 31)), 42);
      expect(seqInYear(202600042, DateTime(2027, 4, 1)), isNull);
      expect(seqInYear(null, DateTime(2027, 4, 1)), isNull);
    });
  });

  group('Extra (off-menu) items', () {
    test('input is validated and cleaned', () {
      final c = CustomItem.parse('  Coke   750 ml ', '45', '2')!;
      expect(c.name, 'Coke 750 ml');
      expect(c.price, 45);
      expect(c.qty, 2);
      expect(CustomItem.parse('Water', '20.555', '1')!.price, 20.56);
      expect(CustomItem.parse('', '20', '1'), isNull);
      expect(CustomItem.parse('Water', '0', '1'), isNull);
      expect(CustomItem.parse('Water', 'abc', '1'), isNull);
      expect(CustomItem.parse('Water', '20', '0'), isNull);
    });

    test('line is billed, marked extra, and not sent to the kitchen', () {
      final line = const CustomItem('Coke', 45, 2).toLine();
      expect(line, {'name': 'Coke', 'price': 45.0, 'size': 'Standard', 'qty': 2, 'isDone': true, 'custom': true});
      final b = Bill.compute(items: [line, {'name': 'Pizza', 'price': 130, 'qty': 1}], gstEnabled: false, gstPercent: 5);
      expect(b.total, 220);
    });

    test('cart merges same extra item, keeps it apart from menu items', () {
      final cart = PosCart();
      cart.addCustom(const CustomItem('Coke', 45, 1).toLine());
      cart.addCustom(const CustomItem('Coke', 45, 2).toLine());
      cart.addCustom(const CustomItem('Coke', 50, 1).toLine());
      expect(cart.lines.length, 2);
      expect(cart.lines.first['qty'], 3);
      expect(cart.itemCount, 4);
    });

    test('editing without new items keeps the kitchen status', () {
      expect(statusAfterEdit('ready', hasNewItems: false), 'ready');
      expect(statusAfterEdit('preparing', hasNewItems: false), 'preparing');
      expect(statusAfterEdit('ready', hasNewItems: true), 'pending');
      expect(statusAfterEdit('weird', hasNewItems: false), 'pending');
    });
  });

  test('itemsSummary lists every item compactly', () {
    expect(
      itemsSummary([
        {'name': 'Farm Villa', 'size': 'Regular', 'qty': 1},
        {'name': 'Pani', 'size': 'Standard', 'qty': 2},
        {'name': 'Coke'},
      ]),
      'Farm Villa (Regular) · 2× Pani · Coke',
    );
    expect(itemsSummary([]), '');
  });
}
