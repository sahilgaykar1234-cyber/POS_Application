import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/web/browser_io.dart';
import '../../core/widgets/ui.dart';
import '../../escpos_bluetooth_printer_stub.dart' if (dart.library.js_interop) '../../escpos_bluetooth_printer_web.dart';
import '../../escpos_usb_printer_stub.dart' if (dart.library.js_interop) '../../escpos_usb_printer_web.dart';
import '../orders/whatsapp_bill.dart';
import '../orders/whatsapp_launch.dart';
import 'receipt_data.dart';
import 'receipt_pdf.dart';
import '../../core/utils/friendly_error.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// Print / WhatsApp / share actions for a SAVED bill. They only read the
/// order they are given (by its id) – they never change the order, its
/// totals or its payment status, and never use the cart being billed.

/// Where a receipt is printed: straight to a thermal printer, by USB cable
/// or Bluetooth (no browser print dialog).
enum ReceiptPrinter {
  usb('USB thermal printer (direct)', Icons.usb_rounded),
  bluetooth('Bluetooth thermal printer', Icons.bluetooth_rounded);

  const ReceiptPrinter(this.englishLabel, this.icon);
  final String englishLabel;
  String get label => tr(englishLabel);
  final IconData icon;

  String get hint => switch (this) {
    ReceiptPrinter.usb => tr('Prints straight to a USB ESC/POS printer (Chrome / Edge)'),
    ReceiptPrinter.bluetooth => EscPosBluetoothPrinter.isSupported
        ? tr('58 mm Bluetooth printer · Chrome on Android or a computer')
        : tr('Not available in this browser – tap to see why'),
  };

  /// Options this device can use. Bluetooth is always listed in the web app:
  /// where the browser can't use it, choosing it explains why.
  static List<ReceiptPrinter> get available => [
    if (EscPosUsbPrinter.isSupported) ReceiptPrinter.usb,
    if (canPrintHtml) ReceiptPrinter.bluetooth,
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
    showError(context, tr('Printing is available in the web app.'));
    return;
  }
  var printer = choose ? null : await savedReceiptPrinter();
  // Only one way to print on this device: no need to ask.
  if (printer == null && options.length == 1 && !choose) printer = options.single;
  if (printer == null) {
    if (!context.mounted) return;
    printer = await chooseReceiptPrinter(context);
    if (printer == null) return;
    await _savePrinter(printer);
    // Picked again on purpose: let them choose the Bluetooth printer again too.
    if (printer == ReceiptPrinter.bluetooth) await EscPosBluetoothPrinter.forgetDevice();
  }
  try {
    switch (printer) {
      case ReceiptPrinter.usb:
        await EscPosUsbPrinter.printReceipt(order: order, orderId: orderId, settings: settings);
      case ReceiptPrinter.bluetooth:
        await EscPosBluetoothPrinter.printReceipt(order: order, orderId: orderId, settings: settings);
    }
  } catch (e) {
    if (context.mounted) showError(context, friendlyPrintError(e));
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
          Text(tr('Print receipt on'), style: ctx.text.titleLarge),
          const SizedBox(height: 4),
          Text(tr('Your choice is remembered on this device.'), style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 13)),
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

/// Sends the FULL bill as a PDF on WhatsApp (same details as the printed
/// receipt). Nothing is sent automatically – staff pick the chat and tap Send.
///  - Phones / tablets: the share sheet opens with the PDF attached → pick
///    WhatsApp → pick the customer's chat → Send.
///  - Computers (no file sharing): the PDF is downloaded and the customer's
///    WhatsApp Web chat opens with a short note → drag the PDF in → Send.
/// If the PDF can't be made, the bill is sent as a text message instead.
Future<void> shareSavedBillOnWhatsApp(
  BuildContext context, {
  required Map<String, dynamic> order,
  required String orderId,
  required Map<String, dynamic> settings,
}) async {
  final r = ReceiptData.from(order, orderId, settings);
  final Uint8List pdf;
  try {
    pdf = await buildReceiptPdf(r);
  } catch (e) {
    debugPrint('Bill PDF not made: $e');
    if (context.mounted) await sendBillTextOnWhatsApp(context, order: order, orderId: orderId, settings: settings);
    return;
  }
  final name = receiptPdfFileName(r);
  if (canShareFile(name, 'application/pdf')) {
    // No text with the file: WhatsApp on iPhone drops the file when both
    // are shared together.
    final result = await shareFile(pdf, name, 'application/pdf');
    if (result != ShareFileResult.unsupported) return;
  }
  downloadFile(pdf, name, 'application/pdf');
  if (!context.mounted) return;
  showSuccess(context, tr('Bill PDF saved – attach it in the WhatsApp chat that opens.'));
  final note = [
    if (r.shopName.isNotEmpty) '*${r.shopName}*',
    'Bill ${r.billNo} · ${receiptMoney(r.total)}',
    'Your bill is attached (PDF).',
  ].join('\n');
  await _openChat(context, order, note);
}

/// The bill typed out as a WhatsApp message (no file).
Future<void> sendBillTextOnWhatsApp(
  BuildContext context, {
  required Map<String, dynamic> order,
  required String orderId,
  required Map<String, dynamic> settings,
}) =>
    _openChat(context, order, buildWhatsAppBill(order: order, orderId: orderId, settings: settings));

/// Opens WhatsApp with [text] for the customer's number (or one typed here,
/// or "choose the chat in WhatsApp").
Future<void> _openChat(BuildContext context, Map<String, dynamic> order, String text) async {
  var number = normalizeWhatsAppNumber((order['customerPhone'] ?? '').toString());
  if (number == null) {
    final entered = await _askNumber(context, (order['customerPhone'] ?? '').toString());
    if (entered == null) return; // cancelled
    if (entered.isEmpty) {
      // "Choose chat in WhatsApp": no number, the user picks the chat there.
      final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showError(context, tr('Could not open WhatsApp.'));
      return;
    }
    number = normalizeWhatsAppNumber(entered);
    if (number == null) {
      if (context.mounted) showError(context, tr('Please enter a valid 10-digit mobile number.'));
      return;
    }
  }
  final ok = await openWhatsAppChat(number, text);
  if (!ok && context.mounted) showError(context, tr('Could not open WhatsApp.'));
}

/// Returns the typed number, '' for "choose the chat in WhatsApp", or null.
Future<String?> _askNumber(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Share bill on WhatsApp')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('This bill has no customer mobile number.'), style: TextStyle(color: ctx.palette.inkSubtle)),
            const SizedBox(height: Space.md),
            TextField(
              key: const Key('wa-number'),
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: InputDecoration(labelText: tr('Customer mobile number'), prefixIcon: Icon(Icons.phone_outlined), hintText: tr('10-digit mobile')),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: Space.sm,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('Choose chat in WhatsApp'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Open WhatsApp'))),
      ],
    ),
  );
}

/// Shares the receipt image: the phone's share sheet (pick WhatsApp) where
/// the browser supports sharing files, otherwise the image is downloaded so
/// it can be attached in WhatsApp Web.
Future<void> shareReceiptImage(BuildContext context, Uint8List png, ReceiptData r) async {
  final name = 'Bill-${r.billNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.png';
  final caption = [if (r.shopName.isNotEmpty) r.shopName, tr('Bill {0}', [r.billNo]), receiptMoney(r.total)].join(' · ');
  if (canShareFile(name, 'image/png')) {
    final result = await shareFile(png, name, 'image/png', text: caption);
    if (result != ShareFileResult.unsupported) return;
  }
  downloadFile(png, name, 'image/png');
  if (context.mounted) showSuccess(context, tr('Receipt image saved – attach it in WhatsApp.'));
}
