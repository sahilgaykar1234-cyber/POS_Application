// OrderService against an in-memory Firestore: bill series, tokens, settle,
// free table, delete and the shared "live" order stream.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/features/orders/bill.dart';
import 'package:pos_app/features/orders/bill_numbers.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/orders/order_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  final svc = OrderService.instance;
  final now = DateTime.now();
  final fy = financialYearShort(now);
  String no(int n) => formatBillNumber(now, n);

  CollectionReference<Map<String, dynamic>> orders() => db.collection('cafes').doc('cafeA').collection('orders');
  DocumentReference<Map<String, dynamic>> billCounter() =>
      db.collection('cafes').doc('cafeA').collection('counters').doc(billCounterName(now));

  Future<({String id, int? token, String? billNo})> place({String table = '1', String type = 'Dine-In', bool billNo = true}) =>
      svc.saveOrder(
        tableNo: table,
        rawName: 'Sahil',
        rawPhone: '',
        orderType: type,
        note: '',
        cart: [
          {'name': 'Margherita', 'price': 200, 'size': 'Regular', 'qty': 1, 'isDone': false},
        ],
        gstEnabled: false,
        gstPercent: 5,
        assignBillNumber: billNo,
      );

  Future<PosOrder> load(String id) async => PosOrder.fromDoc(await orders().doc(id).get());

  setUp(() {
    db = FakeFirebaseFirestore();
    FirestorePaths.overrideDb = db;
    FirestorePaths.setActiveCafe(null);
    FirestorePaths.setActiveCafe('cafeA');
  });

  tearDown(() => FirestorePaths.overrideDb = null);

  group('bill series', () {
    test('new orders are numbered 0001, 0002, 0003 in this year', () async {
      final a = await place(), b = await place(), c = await place();
      expect([a.billNo, b.billNo, c.billNo], [no(1), no(2), no(3)]);
      expect(no(1), '$fy/0001');
      expect((await load(c.id)).billNo, no(3));
      expect((await billCounter().get()).data()!['next'], 4);
    });

    test('continues an existing counter (regression: numbers went missing)', () async {
      await billCounter().set({'next': 5});
      final a = await place();
      expect(a.billNo, no(5));
      expect((await load(a.id)).data['billNo'], no(5));
    });

    test('a new series starts right after the latest existing bill', () async {
      await orders().doc('old').set({'billSeq': 7, 'billFy': financialYear(now), 'billKey': billKey(now, 7), 'billNo': no(7), 'status': 'completed'});
      expect((await place()).billNo, no(8));
    });

    test('legacy bills without billKey are respected', () async {
      await orders().doc('old').set({'billSeq': 3, 'billFy': financialYear(now), 'billNo': no(3), 'status': 'completed'});
      expect((await place()).billNo, no(4));
    });

    test('"Auto bill number" off: no number', () async {
      final a = await place(billNo: false);
      expect(a.billNo, isNull);
      expect((await load(a.id)).data.containsKey('billNo'), isFalse);
    });

    test('takeaway gets a daily token and a bill number', () async {
      final a = await place(table: '', type: 'Takeaway');
      final b = await place(table: '', type: 'Takeaway');
      expect([a.token, b.token], [1, 2]);
      expect([a.billNo, b.billNo], [no(1), no(2)]);
    });
  });

  group('settle / free table', () {
    test('order without a number gets the next one when paid', () async {
      await billCounter().set({'next': 10});
      final a = await place(billNo: false);
      final o = await load(a.id);
      final data = await svc.settle(
        order: o,
        method: PaymentMethod.upi,
        discountType: DiscountType.amount,
        discountValue: 20,
        cashReceived: null,
        complete: true,
      );
      expect(data['billNo'], no(10));
      expect(data['paymentStatus'], 'paid_upi');
      expect(data['totalPrice'], 180);
      expect(data['status'], 'completed');
      expect(data['paidAt'], isA<Timestamp>());
      final saved = await load(a.id);
      expect(saved.billNo, no(10));
      expect(saved.data['discountGiven'], 20);
      expect(saved.isPaid, isTrue);
    });

    test('paying keeps the existing number and does not touch the counter', () async {
      final a = await place();
      final data = await svc.settle(
        order: await load(a.id),
        method: PaymentMethod.cash,
        discountType: DiscountType.none,
        discountValue: 0,
        cashReceived: 500,
        complete: false,
      );
      expect(data['billNo'], no(1));
      expect(data['changeReturned'], 300);
      expect((await billCounter().get()).data()!['next'], 2);
      expect((await load(a.id)).data['cashReceived'], 500);
    });

    test('free table assigns a number if missing', () async {
      final a = await place(billNo: false);
      final data = await svc.complete(await load(a.id));
      expect(data['billNo'], no(1));
      expect((await load(a.id)).isCompleted, isTrue);
    });
  });

  group('delete', () {
    test('deleting the latest bill gives its number to the next order', () async {
      await place();
      final b = await place();
      await svc.delete(b.id);
      await pumpEventQueue();
      expect((await place()).billNo, no(2));
    });

    test('deleting an older bill keeps the series going', () async {
      final a = await place();
      await place();
      await svc.delete(a.id);
      await pumpEventQueue();
      expect((await place()).billNo, no(3));
    });

    test('deleting every bill starts again at 0001', () async {
      final a = await place();
      final b = await place();
      await svc.delete(b.id);
      await pumpEventQueue();
      await svc.delete(a.id);
      await pumpEventQueue();
      expect((await place()).billNo, no(1));
    });
  });

  test('live stream: running orders + recent ones, not old closed bills', () async {
    final old = Timestamp.fromDate(DateTime(now.year, now.month - 3, 5));
    await orders().doc('oldRunning').set({'status': 'pending', 'createdAt': old});
    await orders().doc('oldClosed').set({'status': 'completed', 'createdAt': old});
    await orders().doc('todayClosed').set({'status': 'completed', 'createdAt': Timestamp.fromDate(now)});
    final ids = (await svc.watchLive().first).map((o) => o.id).toSet();
    expect(ids, {'oldRunning', 'todayClosed'});
    final all = (await svc.watchHistory().first).map((o) => o.id).toSet();
    expect(all, {'oldRunning', 'oldClosed', 'todayClosed'});
  });
}
