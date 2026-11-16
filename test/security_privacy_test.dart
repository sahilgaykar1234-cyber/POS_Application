// Bill integrity, Manager PIN, customer privacy, day-end report, plan limits.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/auth/manager_pin.dart';
import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/services/audit_service.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/admin/admin_dialogs.dart';
import 'package:pos_app/features/admin/admin_models.dart';
import 'package:pos_app/features/customers/customer_privacy.dart';
import 'package:pos_app/features/orders/bill.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/orders/void_bill_dialog.dart';
import 'package:pos_app/features/receipt/receipt_data.dart';
import 'package:pos_app/features/receipt/receipt_html.dart';
import 'package:pos_app/features/reports/day_end_report.dart';

import 'layout_test.dart' as lt;

PosOrder bill(String id, {String status = 'completed', String pay = 'paid_cash', double total = 100, int? seq, String phone = '', String name = 'Guest', String type = 'Dine-In', DateTime? at}) =>
    PosOrder(id, {
      'status': status,
      'paymentStatus': pay,
      'totalPrice': total,
      'subtotal': total,
      'orderType': type,
      'customerPhone': phone,
      'customerName': name,
      'billSeq': ?seq,
      if (seq != null) 'billNo': '26-27/${seq.toString().padLeft(4, '0')}',
      'createdAt': Timestamp.fromDate(at ?? DateTime(2026, 11, 16, 20)),
    });

void main() {
  group('Manager PIN', () {
    test('only a salted hash is kept; right PIN opens, wrong does not', () {
      final salt = ManagerPin.newSalt();
      final hash = ManagerPin.hash('4321', salt);
      expect(hash, isNot(contains('4321')));
      expect(ManagerPin.matches('4321', salt: salt, hash: hash), isTrue);
      expect(ManagerPin.matches('1234', salt: salt, hash: hash), isFalse);
      expect(ManagerPin.hash('4321', ManagerPin.newSalt()), isNot(hash), reason: 'different salt, different hash');
      expect(ManagerPin.isValid('123'), isFalse);
      expect(ManagerPin.isValid('1234'), isTrue);
      expect(ManagerPin.isValid('12a4'), isFalse);
    });
  });

  test('phone masking', () {
    expect(maskPhone('9825012345'), '98XXXXX345');
    expect(maskPhone(''), '');
  });

  group('customer privacy', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      FirestorePaths.overrideDb = db;
      FirestorePaths.setActiveCafe(null);
      FirestorePaths.setActiveCafe('c1');
      final orders = db.collection('cafes').doc('c1').collection('orders');
      await orders.doc('a').set({...bill('a', phone: '9825012345', name: 'Sahil (Table 4)', total: 300).data, 'tableNo': '4'});
      await orders.doc('b').set({...bill('b', phone: '9825012345', name: 'Sahil').data});
      await orders.doc('c').set({...bill('c', phone: '9000011111', name: 'Priya').data});
      await orders.doc('old').set({...bill('old', phone: '9111111111', name: 'Old', at: DateTime(2023, 1, 1)).data});
    });
    tearDown(() => FirestorePaths.overrideDb = null);

    test('"delete my data" clears name and number on all their bills, keeps the bills', () async {
      expect(await CustomerPrivacy.instance.removeCustomer(phone: '9825012345', name: 'Sahil'), 2);
      final a = (await db.doc('cafes/c1/orders/a').get()).data()!;
      expect(a['customerPhone'], '');
      expect(a['customerName'], 'Guest (Table 4)');
      expect(a['totalPrice'], 300, reason: 'amounts stay');
      expect((await db.doc('cafes/c1/orders/c').get()).data()!['customerPhone'], '9000011111');
    });

    test('old numbers are removed after the chosen months', () async {
      expect(await CustomerPrivacy.instance.removeOlderThan(24, now: DateTime(2026, 11, 16)), 1);
      expect((await db.doc('cafes/c1/orders/old').get()).data()!['customerPhone'], '');
      expect((await db.doc('cafes/c1/orders/a').get()).data()!['customerPhone'], '9825012345');
    });
  });

  group('day-end report', () {
    final orders = [
      bill('1', seq: 41, total: 200),
      bill('2', seq: 42, total: 300, pay: 'paid_upi', type: 'Takeaway'),
      bill('3', seq: 43, total: 150, pay: 'pending', status: 'pending'),
      bill('4', seq: 44, total: 500, status: 'cancelled'),
    ];
    test('totals per method, unpaid and cancelled kept apart', () {
      final s = DayEndSummary.of(orders);
      expect(s.bills, 3);
      expect(s.firstBill, '26-27/0041');
      expect(s.lastBill, '26-27/0044');
      expect(s.billed, 650);
      expect(s.collected, 500);
      expect(s.byMethod[PaymentMethod.cash], 200);
      expect(s.byMethod[PaymentMethod.upi], 300);
      expect(s.unpaidCount, 1);
      expect(s.unpaidAmount, 150);
      expect(s.cancelledCount, 1);
      expect(s.cancelledAmount, 500);
      expect(s.takeaway, 1);
    });
    test('printable', () {
      final html = dayEndHtml(DayEndSummary.of(orders), shopName: 'Flammy Wood', periodLabel: 'Business day 16 Nov 2026', printedAt: DateTime(2026, 11, 17, 1));
      expect(html, contains('DAY-END REPORT'));
      expect(html, contains('₹650.00'));
      expect(html, contains('Cancelled (1)'));
    });
  });

  test('a cancelled bill says so on the receipt and the printout', () {
    final o = {...bill('v', seq: 9).data, 'status': 'cancelled', 'voidReason': 'Wrong order'};
    final r = ReceiptData.from(o, 'v');
    expect(r.isCancelled, isTrue);
    expect(receiptHtml(r, PaperSize.thermal80), contains('CANCELLED · Wrong order'));
  });

  group('plan login limit', () {
    final cafe = CafeSummary('c1', {'name': 'Cafe', 'subscription': {'planId': 'basic', 'planName': 'Basic', 'status': 'active'}});
    final plans = [SubscriptionPlan('basic', const {'name': 'Basic', 'tier': 'basic', 'maxStaff': 2})];
    final staff = [
      StaffMember('a', const {'cafeId': 'c1', 'role': 'manager'}),
      StaffMember('b', const {'cafeId': 'c1', 'role': 'captain'}),
      StaffMember('c', const {'cafeId': 'c1', 'role': 'captain', 'status': 'disabled'}),
    ];
    test('counts only active logins of the cafe', () {
      expect(loginAllowance(cafe, plans, staff), (max: 2, used: 2));
      expect(loginAllowance(CafeSummary('x', const {}), plans, staff).max, isNull);
    });
    testWidgets('adding a login past the limit explains instead of creating', (t) async {
      await lt.pumpAt(
        t,
        lt.sizes['desktop']!,
        Builder(builder: (c) => TextButton(onPressed: () => showAddLogin(c, cafe, plans: plans, staff: staff), child: const Text('open'))),
        AppTheme.light(),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Login limit reached'), findsOneWidget);
      expect(find.byKey(const Key('login-username')), findsNothing);
    });
  });

  testWidgets('cancelling a bill needs a reason', (t) async {
    await lt.pumpAt(
      t,
      lt.sizes['phone']!,
      Builder(builder: (c) => TextButton(onPressed: () => showVoidBillDialog(c, bill('x', seq: 5)), child: const Text('open'))),
      AppTheme.light(),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final confirm = find.byKey(const Key('void-confirm'));
    expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'no reason yet');
    await t.tap(find.byKey(const Key('void-Wrong order')));
    await t.pump();
    expect(t.widget<FilledButton>(confirm).onPressed, isNotNull);
    await t.tap(find.text('Keep bill'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
