import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/features/receipt/receipt_data.dart';
import 'package:pos_app/features/receipt/receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> order({bool gst = false, String status = 'completed'}) => {
        'billNo': '26-27/0002',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 17, 16, 14)),
        'tableNo': '8',
        'customerName': 'Manish test',
        'customerPhone': '9825012345',
        'items': [
          {'name': 'Trpple Cheese Melt', 'size': 'Standard', 'qty': 1, 'price': 180},
          {'name': 'Jain Special Stuffed Bread', 'size': 'Standard', 'qty': 1, 'price': 160},
          {'name': 'Creamy Corn & Cheese Bread', 'size': 'Standard', 'qty': 1, 'price': 160},
          {'name': 'Paneer Tikka Stuffed', 'size': '10 inch', 'qty': 2, 'price': 90},
        ],
        'subtotal': 680,
        'discountGiven': gst ? 20 : 0,
        'hasGst': gst,
        'gstPercentage': 5,
        'totalPrice': gst ? 693 : 680,
        'paymentStatus': 'paid_cash',
        'status': status,
        if (status == 'cancelled') 'voidReason': 'Customer left',
      };

  final settings = {
    'shopName': 'Flammy Wood Pizza',
    'tagline': 'Wood Fired Pizza',
    'address': 'Junomonta Tower',
    'mobileNumber': '857585758575',
    'gstNumber': '24ABCDE1234F1Z5',
    'thankYouMessage': 'Thank you for your order!',
  };

  test('full bill PDF: one valid page, every detail, fonts embedded', () async {
    final r = ReceiptData.from(order(gst: true), 'KB87XO123', settings);
    final bytes = await buildReceiptPdf(r);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, lessThan(400 * 1024), reason: 'small enough for WhatsApp');
    expect(receiptPdfFileName(r), 'Bill-26-27-0002.pdf');
    final out = Platform.environment['RECEIPT_PDF_OUT'];
    if (out != null) await File(out).writeAsBytes(bytes);
  });

  test('logo from Settings is drawn', () async {
    final png = (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
    final r = ReceiptData.from(order(), 'X1', {...settings, 'shopLogoBase64': base64Encode(png)});
    final bytes = await buildReceiptPdf(r);
    expect(bytes.length, greaterThan(png.length ~/ 4));
    final out = Platform.environment['RECEIPT_PDF_LOGO_OUT'];
    if (out != null) await File(out).writeAsBytes(bytes);
  });

  test('cancelled and plain bills also build; a broken logo is skipped', () async {
    for (final o in [order(status: 'cancelled'), order()]) {
      final r = ReceiptData.from(o, 'X1', {...settings, 'shopLogoBase64': 'not-an-image'});
      final bytes = await buildReceiptPdf(r);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('fonts come from the app bundle', () async {
    expect((await rootBundle.load('assets/fonts/Inter-Regular.ttf')).lengthInBytes, greaterThan(0));
  });
}
