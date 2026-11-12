import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/orders/orders_filter.dart';
import 'package:pos_app/features/receipt/receipt_data.dart';
import 'package:pos_app/features/receipt/receipt_html.dart';

Map<String, dynamic> paidOrder() => {
      'billNo': '26-27/0042',
      'customerName': 'Sahil (Table 4)',
      'customerPhone': '9825012345',
      'tableNo': '4',
      'orderType': 'Dine-In',
      'status': 'completed',
      'paymentStatus': 'paid_upi',
      'items': [
        {'name': 'Farm Villa', 'size': 'Regular', 'price': 240, 'qty': 2},
        {'name': 'Pani', 'size': 'Standard', 'price': 20, 'qty': 1, 'custom': true},
      ],
      // Saved amounts (prices may have changed in the menu since).
      'subtotal': 500,
      'discountGiven': 50,
      'hasGst': true,
      'gstPercentage': 5,
      'totalPrice': 472.5,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 12, 19, 5)),
      'paidAt': Timestamp.fromDate(DateTime(2026, 11, 12, 20, 15)),
    };

const settings = {'shopName': 'Pizza La Forno', 'thankYouMessage': 'Thank You!', 'receiptFooter': 'Visit Again!'};

void main() {
  group('ReceiptData', () {
    test('uses the saved amounts, never recalculates', () {
      final r = ReceiptData.from(paidOrder(), 'kb87xoAbc', settings);
      expect(r.billNo, '26-27/0042');
      expect(r.orderRef, '#KB87XO');
      expect(r.subtotal, 500);
      expect(r.discount, 50);
      expect(r.taxable, 450);
      expect(r.gst, 22.5);
      expect(r.cgst, 11.25);
      expect(r.sgst, 11.25);
      expect(r.total, 472.5);
      expect(r.lines.first.amount, 480);
      expect(r.lines.first.variant, 'Regular');
      expect(r.lines.last.variant, '');
      expect(r.lines.last.extra, isTrue);
      expect(r.itemCount, 3);
    });

    test('payment and labels', () {
      final r = ReceiptData.from(paidOrder(), 'x', settings);
      expect(r.isPaid, isTrue);
      expect(r.paymentMethod, 'UPI');
      expect(r.paymentLabel, 'Paid · UPI');
      expect(r.customerName, 'Sahil');
      expect(r.whereLabel, 'Table 4');
      expect(r.billTime, DateTime(2026, 11, 12, 20, 15));
      expect(r.statusLabel, 'Completed');
    });

    test('unpaid, no GST, legacy order without subtotal', () {
      final r = ReceiptData.from({
        'paymentStatus': 'pending',
        'status': 'pending',
        'items': [
          {'name': 'Tea', 'price': 15, 'qty': 2},
        ],
        'totalPrice': 30,
        'tableNo': '',
        'orderType': 'Takeaway',
        'tokenNo': 7,
      }, 'abcdefgh');
      expect(r.isPaid, isFalse);
      expect(r.paymentLabel, 'Payment pending');
      expect(r.hasGst, isFalse);
      expect(r.subtotal, 30);
      expect(r.billNo, '#ABCDEF');
      expect(r.whereLabel, 'Takeaway · Token #7');
      expect(r.shopName, '');
    });

    test('money format', () {
      expect(receiptMoney(1234567.5, always2: true), '₹12,34,567.50');
      expect(receiptMoney(240), '₹240');
      expect(receiptDate(DateTime(2026, 11, 12, 0, 5)), '12 Nov 2026, 12:05 AM');
    });
  });

  group('print HTML', () {
    test('80mm receipt has the bill and the GST split, sized for the paper', () {
      final html = receiptHtml(ReceiptData.from(paidOrder(), 'x', settings), PaperSize.thermal80);
      expect(html, contains('size: 80mm auto'));
      expect(html, contains('26-27/0042'));
      expect(html, contains('Farm Villa (Regular)'));
      expect(html, contains('CGST 2.5%'));
      expect(html, contains('₹472.50'));
      expect(html, contains('PAID'));
      expect(html, isNot(contains('GSTIN'))); // not configured: not invented
    });

    test('A4 and escaping', () {
      final o = paidOrder()..['items'] = [
          {'name': '<b>Pizza</b> & Co', 'price': 100, 'qty': 1},
        ];
      final html = receiptHtml(ReceiptData.from(o, 'x', {'shopName': 'A&B', 'gstNumber': '24ABC'}), PaperSize.a4);
      expect(html, contains('size: A4;'));
      expect(html, contains('&lt;b&gt;Pizza&lt;/b&gt; &amp; Co'));
      expect(html, contains('GSTIN: 24ABC'));
      expect(html, isNot(contains('<b>Pizza')));
    });
  });

  group('orders filter', () {
    PosOrder o(String id, {String status = 'completed', String pay = 'paid_cash', String name = 'Guest', String table = '', int min = 0}) =>
        PosOrder(id, {
          'status': status,
          'paymentStatus': pay,
          'customerName': name,
          'tableNo': table,
          'billNo': '26-27/00$id',
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 12, 10, min)),
        });
    final all = [o('01', min: 1), o('02', status: 'pending', pay: 'pending', min: 2, table: '4'), o('03', pay: 'paid_upi', name: 'Rahul', min: 3), o('04', status: 'cancelled', min: 4)];

    test('newest first, search by bill / name / table', () {
      expect(filterOrders(all).map((x) => x.id), ['04', '03', '02', '01']);
      expect(filterOrders(all, search: '0003').single.id, '03');
      expect(filterOrders(all, search: 'rahul').single.id, '03');
      expect(filterOrders(all, search: 'table 4').single.id, '02');
    });

    test('status and payment filters', () {
      expect(filterOrders(all, status: OrderStatusFilter.running).single.id, '02');
      expect(filterOrders(all, status: OrderStatusFilter.cancelled).single.id, '04');
      expect(filterOrders(all, payment: PaymentFilter.unpaid).single.id, '02');
      expect(filterOrders(all, payment: PaymentFilter.upi).single.id, '03');
      expect(filterOrders(all, payment: PaymentFilter.paid).length, 3);
    });

    test('date presets and pages', () {
      final now = DateTime(2026, 11, 12, 15);
      // Business days end at 5:00 AM (default).
      expect(DatePreset.today.range(now), (DateTime(2026, 11, 12, 5), DateTime(2026, 11, 13, 5)));
      expect(DatePreset.yesterday.range(now), (DateTime(2026, 11, 11, 5), DateTime(2026, 11, 12, 5)));
      expect(DatePreset.last7.range(now)!.$1, DateTime(2026, 11, 6, 5));
      expect(DatePreset.thisMonth.range(now)!.$1, DateTime(2026, 11, 1, 5));
      // 1:30 AM is still "yesterday night", i.e. today's business day of the 11th.
      expect(DatePreset.today.range(DateTime(2026, 11, 12, 1, 30))!.$1, DateTime(2026, 11, 11, 5));
      expect(pageOf([1, 2, 3, 4, 5], 1, 2), [3, 4]);
      expect(pageOf([1, 2, 3], 5, 2), isEmpty);
    });
  });
}
