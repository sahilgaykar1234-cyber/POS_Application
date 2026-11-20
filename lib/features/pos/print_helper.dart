import 'package:flutter/material.dart';

import '../receipt/receipt_actions.dart';

/// Prints a bill (also one not saved yet) on the printer chosen on this
/// device – USB, Bluetooth or the print dialog – showing any error nicely.
Future<void> printBill(BuildContext context, {required Map<String, dynamic> order, required Map<String, dynamic> settings, String? orderId}) =>
    printSavedBill(context, order: order, orderId: orderId ?? '', settings: settings);
