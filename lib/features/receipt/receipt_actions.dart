import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/web/browser_io.dart';
import '../../core/widgets/ui.dart';
import '../../escpos_usb_printer_stub.dart' if (dart.library.js_interop) '../../escpos_usb_printer_web.dart';
import '../orders/whatsapp_bill.dart';
import '../orders/whatsapp_launch.dart';
import 'receipt_data.dart';
import 'receipt_html.dart';

/// Print / WhatsApp / share actions for a SAVED bill. They only read the
/// order they are given (by its id) – they never change the order, its
/// totals or its payment status, and never use the cart being billed.

/// Where a receipt is printed.
enum ReceiptPrinter {
  thermal80('80 mm receipt printer', Icons.receipt_long_outlined),
  thermal58('58 mm receipt printer', Icons.receipt_outlined),
  a4('A4 / normal printer', Icons.description_outlined),
  usb('USB thermal printer (direct)', Icons.usb_rounded);

  const ReceiptPrinter(this.label, this.icon);
  final String label;
  final IconData icon;

  String get hint => switch (this) {
        ReceiptPrinter.usb => 'Prints straight to a USB ESC/POS printer (Chrome / Edge)',
        ReceiptPrinter.a4 => 'Opens the print dialog with an A4 page',
        _ => 'Opens the print dialog sized for receipt paper',
      };

  PaperSize? get paper => switch (this) {
        ReceiptPrinter.thermal80 => PaperSize.thermal80,
        ReceiptPrinter.thermal58 => PaperSize.thermal58,
        ReceiptPrinter.a4 => PaperSize.a4,
        ReceiptPrinter.usb => null,
      };

  /// Options this device can use.
  static List<ReceiptPrinter> get available => [
        if (canPrintHtml) ...[ReceiptPrinter.thermal80, ReceiptPrinter.thermal58, ReceiptPrinter.a4],
        if (EscPosUsbPrinter.isSupported) ReceiptPrinter.usb,
      ];
}

const _prefKey = 'cafe_pos_receipt_printer';

Future<ReceiptPrinter?> savedReceiptPrinter() async {
  try {
    final name = (await SharedPreferences.getInstance()).getString(_prefKey);
    final p = ReceiptPrinter.values.where((e) => e.name == name).firstOrNull;
    return p != null && ReceiptPrinter.available.contains(p) ? p : null;
  } catch (_) {
    return null;
  }
}

Future<void> _savePrinter(ReceiptPrinter p) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_prefKey, p.name);
  } catch (_) {}
}

/// Prints the saved bill [order] (id [orderId]). Uses the printer chosen
/// last time; asks the first time or when [choose] is true.
Future<void> printSavedBill(
  BuildContext context, {
  required Map<String, dynamic> order,
  required String orderId,
  required Map<String, dynamic> settings,
  bool choose = false,
}) async {
  final options = ReceiptPrinter.available;
  if (options.isEmpty) {
    showError(context, 'Printing is available in the web app.');
    return;
  }
  var printer = choose ? null : await savedReceiptPrinter();
  if (printer == null) {
    if (!context.mounted) return;
    printer = await chooseReceiptPrinter(context);
    if (printer == null) return;
    await _savePrinter(printer);
  }
  try {
    final paper = printer.paper;
    if (paper == null) {
      await EscPosUsbPrinter.printReceipt(order: order, orderId: orderId, settings: settings);
    } else {
      await printHtml(receiptHtml(ReceiptData.from(order, orderId, settings), paper));
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Could not print: $e');
  }
}

/// Lets the user pick the printer / paper size.
Future<ReceiptPrinter?> chooseReceiptPrinter(BuildContext context) async {
  final current = await savedReceiptPrinter();
  if (!context.mounted) return null;
  return showModalBottomSheet<ReceiptPrinter>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Print receipt on', style: ctx.text.titleLarge),
          const SizedBox(height: 4),
          Text('Your choice is remembered on this device.', style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 13)),
          const SizedBox(height: Space.md),
          for (final p in ReceiptPrinter.available)
            ListTile(
              key: Key('printer-${p.name}'),
              leading: Icon(p.icon),
              title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(p.hint),
              trailing: p == current ? Icon(Icons.check_circle_rounded, color: ctx.palette.success) : null,
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    ),
  );
}

/// Opens WhatsApp with the bill typed in, for the customer's number (or one
/// typed here). The user reviews it and taps Send in WhatsApp – nothing is
/// sent automatically, and we never claim it was delivered.
Future<void> shareSavedBillOnWhatsApp(
  BuildContext context, {
  required Map<String, dynamic> order,
  required String orderId,
  required Map<String, dynamic> settings,
}) async {
  final text = buildWhatsAppBill(order: order, orderId: orderId, settings: settings);
  var number = normalizeWhatsAppNumber((order['customerPhone'] ?? '').toString());
  if (number == null) {
    final entered = await _askNumber(context, (order['customerPhone'] ?? '').toString());
    if (entered == null) return; // cancelled
    if (entered.isEmpty) {
      // "Choose chat in WhatsApp": no number, the user picks the chat there.
      final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showError(context, 'Could not open WhatsApp.');
      return;
    }
    number = normalizeWhatsAppNumber(entered);
    if (number == null) {
      if (context.mounted) showError(context, 'Please enter a valid 10-digit mobile number.');
      return;
    }
  }
  final ok = await openWhatsAppChat(number, text);
  if (!ok && context.mounted) showError(context, 'Could not open WhatsApp.');
}

/// Returns the typed number, '' for "choose the chat in WhatsApp", or null.
Future<String?> _askNumber(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Share bill on WhatsApp'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('This bill has no customer mobile number.', style: TextStyle(color: ctx.palette.inkSubtle)),
            const SizedBox(height: Space.md),
            TextField(
              key: const Key('wa-number'),
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(labelText: 'Customer mobile number', prefixIcon: Icon(Icons.phone_outlined), hintText: '10-digit mobile'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: Space.sm,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Choose chat in WhatsApp')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Open WhatsApp')),
      ],
    ),
  );
}

/// Shares the receipt image: the phone's share sheet (pick WhatsApp) where
/// the browser supports sharing files, otherwise the image is downloaded so
/// it can be attached in WhatsApp Web.
Future<void> shareReceiptImage(BuildContext context, Uint8List png, ReceiptData r) async {
  final name = 'Bill-${r.billNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.png';
  final caption = [if (r.shopName.isNotEmpty) r.shopName, 'Bill ${r.billNo}', receiptMoney(r.total)].join(' · ');
  if (canShareFile(name, 'image/png')) {
    final result = await shareFile(png, name, 'image/png', text: caption);
    if (result != ShareFileResult.unsupported) return;
  }
  downloadFile(png, name, 'image/png');
  if (context.mounted) showSuccess(context, 'Receipt image saved – attach it in WhatsApp.');
}
