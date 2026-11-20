import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/utils/friendly_error.dart';
import 'package:pos_app/features/receipt/bluetooth_printer_logic.dart';
import 'package:pos_app/features/receipt/escpos_receipt.dart';
import 'package:pos_app/features/receipt/receipt_actions.dart';

bool hasBytes(Uint8List all, List<int> part) {
  for (var i = 0; i + part.length <= all.length; i++) {
    var ok = true;
    for (var j = 0; j < part.length && ok; j++) {
      ok = all[i + j] == part[j];
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('ESC/POS receipt (USB and Bluetooth share it)', () {
    final order = {
      'billNo': '26-27/0042',
      'tableNo': '4',
      'customerName': 'Ravi',
      'paymentStatus': 'paid_upi',
      'subtotal': 600.0,
      'totalPrice': 630.0,
      'hasGst': true,
      'gstPercentage': 5.0,
      'items': [
        {'name': 'Margherita', 'size': '10 inch', 'price': 300.0, 'qty': 2},
      ],
    };
    final settings = {'shopName': 'Flammy Wood', 'showGst': true, 'gstPercentage': '5', 'thankYouMessage': 'Thank you!'};

    test('has the bill, items, total, then feed and cut', () async {
      final bytes = await EscPosReceipt.build(order: order, settings: settings, orderId: 'ORD1');
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(text, contains('FLAMMY'));
      expect(text, contains('Table 4'));
      expect(text, contains('Margherita (10')); // long names wrap on 58 mm paper
      expect(text, contains('inch)'));
      expect(text, contains('GRAND TOTAL:'));
      expect(text, contains('Rs 630.00'));
      expect(text, contains('Mode: UPI'));
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(text.split('\n').where((l) => l.replaceAll(RegExp(r'[\x00-\x1F]'), '').length > EscPosReceipt.lineWidth + 3), isEmpty);
    });

    test('building twice gives the same bytes (no leftovers)', () async {
      final a = await EscPosReceipt.build(order: order, settings: settings, orderId: 'ORD1');
      final b = await EscPosReceipt.build(order: order, settings: settings, orderId: 'ORD1');
      expect(a, b);
      expect(hasBytes(a, [0x1B, 0x45, 1]), isTrue); // bold used
    });
  });

  group('Bluetooth printer', () {
    test('a known printer characteristic is preferred', () {
      final pick = pickPrinterCharacteristic(const [
        BtCharacteristic('0000ffe1-0000-1000-8000-00805f9b34fb', write: true),
        BtCharacteristic('00002af1-0000-1000-8000-00805f9b34fb', writeWithoutResponse: true),
        BtCharacteristic('00002a19-0000-1000-8000-00805f9b34fb'),
      ]);
      expect(pick!.uuid, '00002af1-0000-1000-8000-00805f9b34fb');
    });

    test('an unknown printer still works if something is writable; nothing writable = not a printer', () {
      expect(pickPrinterCharacteristic(const [BtCharacteristic('0000abcd-0000-1000-8000-00805f9b34fb', write: true)])!.uuid,
          '0000abcd-0000-1000-8000-00805f9b34fb');
      expect(pickPrinterCharacteristic(const [BtCharacteristic('00002a19-0000-1000-8000-00805f9b34fb')]), isNull);
      expect(pickPrinterCharacteristic(const []), isNull);
    });

    test('data is sent in small pieces, in order, nothing lost', () {
      final data = Uint8List.fromList(List.generate(45, (i) => i));
      final parts = chunked(data);
      expect(parts.map((p) => p.length), [20, 20, 5]);
      expect(parts.expand((p) => p).toList(), data);
      expect(chunked(Uint8List(0)), isEmpty);
    });

    test('printer problems become plain messages', () {
      expect(friendlyPrintError(const PrinterProblem('bt-connect')), contains('Turn it on'));
      expect(friendlyPrintError(const PrinterProblem('bt-write')), contains('off and on'));
      expect(friendlyPrintError(const PrinterProblem('bt-not-printer')), contains('choose your printer'));
      expect(friendlyPrintError(const PrinterProblem('bt-unsupported:ios|Safari 18')), contains('Bluefy'));
      expect(friendlyPrintError(const PrinterProblem('bt-unsupported:browser|Samsung Internet 27')), contains('Samsung Internet 27'));
      expect(friendlyPrintError(const PrinterProblem('bt-unsupported')), contains('Google Chrome'));
      expect(friendlyPrintError('NotFoundError: User cancelled the requestDevice() chooser.'), 'No printer was selected.');
    });

    test('why a browser can\'t print by Bluetooth', () {
      const chrome = 'Mozilla/5.0 (Linux; Android 13; RMX3511) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
      const samsung = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/27.0 Chrome/125.0 Mobile Safari/537.36';
      const webView = 'Mozilla/5.0 (Linux; Android 13; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0 Mobile Safari/537.36';
      const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 Mobile/15E148 Safari/604.1';
      expect(bluetoothBlockedReason(userAgent: chrome, hasApi: true, secure: true), isNull);
      expect(bluetoothBlockedReason(userAgent: chrome, hasApi: false, secure: false), 'insecure');
      expect(bluetoothBlockedReason(userAgent: samsung, hasApi: false, secure: true), 'browser');
      expect(bluetoothBlockedReason(userAgent: webView, hasApi: false, secure: true), 'in-app');
      expect(bluetoothBlockedReason(userAgent: iphone, hasApi: false, secure: true), 'ios');
      expect(bluetoothBlockedReason(userAgent: chrome, hasApi: false, secure: true), 'other');
      expect(browserLabel(samsung), 'Samsung Internet 27');
      expect(browserLabel(chrome), 'Chrome 131');
    });

    test('Bluetooth is listed only in the web app (not in tests)', () {
      expect(ReceiptPrinter.available, isNot(contains(ReceiptPrinter.bluetooth)));
      expect(ReceiptPrinter.values, [ReceiptPrinter.usb, ReceiptPrinter.bluetooth]);
    });
  });
}
