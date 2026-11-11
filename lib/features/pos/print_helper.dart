import 'package:flutter/material.dart';

import '../../core/widgets/ui.dart';
import '../../escpos_usb_printer_stub.dart' if (dart.library.js_interop) '../../escpos_usb_printer_web.dart';

/// Prints a bill on the USB thermal printer (web), showing any error nicely.
Future<void> printBill(
  BuildContext context, {
  required Map<String, dynamic> order,
  required Map<String, dynamic> settings,
  String? orderId,
}) async {
  try {
    await EscPosUsbPrinter.printReceipt(order: order, orderId: orderId, settings: settings);
  } catch (e) {
    if (context.mounted) showError(context, 'Print error: $e');
  }
}
