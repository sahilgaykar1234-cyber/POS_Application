import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/orders/whatsapp_bill.dart';

import 'core/theme/tokens.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'escpos_usb_printer_stub.dart' if (dart.library.js_interop) 'escpos_usb_printer_web.dart';

class PaymentCompleteReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderId;
  final Map<String, dynamic>? businessSettings;

  const PaymentCompleteReceiptScreen({super.key, required this.orderData, required this.orderId, this.businessSettings});

  @override
  Widget build(BuildContext context) {
    // 1. Fetch dynamic settings from businessSettings or Fallback
    final String? shopLogoBase64 = businessSettings?['shopLogoBase64'];
    final String shopName = (businessSettings?['shopName'] ?? '').toString();
    final String tagline = (businessSettings?['tagline'] ?? 'Wood Fired Pizza').toString();
    final String address = (businessSettings?['address'] ?? '').toString();
    final String mobileNumber = (businessSettings?['mobileNumber'] ?? '').toString();
    final String gstNumber = (businessSettings?['gstNumber'] ?? '').toString();

    final String receiptHeader = (businessSettings?['receiptHeader'] ?? 'Thank you for your order!').toString();
    final String receiptFooter = (businessSettings?['receiptFooter'] ?? 'Visit Again!').toString();
    final String thankYouMessage = (businessSettings?['thankYouMessage'] ?? 'Thank You!').toString();

    final bool showGst = businessSettings?['showGst'] == true || orderData['hasGst'] == true;
    final double gstPercentage =
        double.tryParse((businessSettings?['gstPercentage'] ?? orderData['gstPercentage'] ?? '5').toString()) ?? 5.0;

    // 2. Order Information
    final String billNo = '#${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length).toUpperCase()}';
    final String customerName = (orderData['customerName'] ?? 'Walk-in Guest').toString();
    final String customerPhone = (orderData['customerPhone'] ?? '').toString();
    final String tableNo = (orderData['tableNo'] ?? '').toString();
    final String paymentMode = (orderData['paymentStatus'] ?? 'PAID').toString().replaceAll('paid_', '').toUpperCase();

    DateTime orderTime = DateTime.now();
    if (orderData['completedAt'] != null && orderData['completedAt'] is Timestamp) {
      orderTime = (orderData['completedAt'] as Timestamp).toDate();
    } else if (orderData['createdAt'] != null && orderData['createdAt'] is Timestamp) {
      orderTime = (orderData['createdAt'] as Timestamp).toDate();
    }

    final String dateStr = '${orderTime.day.toString().padLeft(2, '0')}/${orderTime.month.toString().padLeft(2, '0')}/${orderTime.year}';
    final String timeStr = '${orderTime.hour.toString().padLeft(2, '0')}:${orderTime.minute.toString().padLeft(2, '0')}';

    final List items = orderData['items'] ?? [];
    final double subtotal = (orderData['subtotal'] ?? orderData['totalPrice'] ?? 0.0).toDouble();
    final double grandTotal = (orderData['totalPrice'] ?? subtotal).toDouble();
    // Discount (if any) is taken off before GST; old bills have none.
    final double discount = ((orderData['discountGiven'] ?? 0) as num).toDouble();
    final double taxable = subtotal - discount;
    final double taxAmount = showGst ? (grandTotal - taxable > 0 ? grandTotal - taxable : taxable * (gstPercentage / 100.0)) : 0.0;

    final p = context.palette;
    Future<void> printNow() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await EscPosUsbPrinter.printReceipt(order: orderData, orderId: orderId, settings: businessSettings ?? {});
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Print error: $e')));
      }
    }

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: Text('Bill $billNo'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  children: [
                    // On phones the app bar's ✕ already closes, so skip "Done".
                    if (c.maxWidth >= 400) ...[
                      Expanded(
                        child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF128C4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () => _sendOnWhatsApp(context),
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                        onPressed: printNow,
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Print'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 380), // 80mm thermal paper, shrinks on small phones
            padding: const EdgeInsets.all(22.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.border),
              boxShadow: const [BoxShadow(color: Color(0x14101828), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 🟢 1. HEADER & LOGO SECTION (UPLOADED BRANDING IMAGE FROM SETTINGS)
                Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (shopLogoBase64 != null && shopLogoBase64.isNotEmpty)
                        ? Image.memory(
                            base64Decode(shopLogoBase64),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.storefront_rounded, color: Colors.black54, size: 34);
                            },
                          )
                        : Container(
                            color: Colors.black12,
                            child: const Icon(Icons.storefront_rounded, color: Colors.black54, size: 34),
                          ),
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  shopName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 1.1,
                  ),
                ),

                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87),
                  ),
                ],

                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black54),
                  ),
                ],

                if (mobileNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Phone: $mobileNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],

                if (gstNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'GSTIN: $gstNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ],

                const SizedBox(height: 10),
                _buildDottedDivider(),
                const SizedBox(height: 8),

                // 🟢 HEADER GREETING MESSAGE
                if (receiptHeader.isNotEmpty) ...[
                  Text(
                    receiptHeader,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                ],

                // 🟢 BILL DETAILS (BILL NO, DATE, TIME, TABLE, CUSTOMER)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Text(
                      'Bill: $billNo',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    Text(
                      '$dateStr $timeStr',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Text(
                      tableNo.isNotEmpty ? (tableNo.toLowerCase().contains('table') ? tableNo : 'Table $tableNo') : 'Counter / Takeaway',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    Text(
                      'Mode: $paymentMode',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ],
                ),
                if (customerName.isNotEmpty && customerName.toLowerCase() != 'walk-in guest') ...[
                  const SizedBox(height: 3),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      Text(
                        'Customer: $customerName',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                      ),
                      if (customerPhone.isNotEmpty)
                        Text(
                          customerPhone,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Colors.black54),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                // 🟢 2. ITEMS TABLE (QTY, ITEM NAME, PRICE)
                Row(
                  children: const [
                    Expanded(
                      flex: 5,
                      child: Text(
                        'ITEM',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'QTY',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'AMOUNT',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                ...items.map<Widget>((item) {
                  final String name = (item['name'] ?? 'Item').toString();
                  final String size = (item['size'] ?? '').toString();
                  final int qty = (item['qty'] ?? 1);
                  final double price = (item['price'] ?? 0.0).toDouble();
                  final double itemTotal = price * qty;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            size.isNotEmpty && size != 'Standard' ? '$name ($size)' : name,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '$qty',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '₹${itemTotal.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 6),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                // 🟢 3. TOTALS & TAX
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    const Text(
                      'Subtotal:',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                    ),
                    Text(
                      '₹${subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                    ),
                  ],
                ),

                if (discount > 0) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      const Text(
                        'Discount:',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                      ),
                      Text(
                        '-₹${discount.toStringAsFixed(2)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                      ),
                    ],
                  ),
                ],

                if (showGst) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      Text(
                        'GST ($gstPercentage%):',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                      ),
                      Text(
                        '₹${taxAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 6),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    const Text(
                      'GRAND TOTAL:',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    Text(
                      '₹${grandTotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _buildDottedDivider(),
                const SizedBox(height: 12),

                // 🟢 4. FOOTER & THANK YOU
                if (thankYouMessage.isNotEmpty) ...[
                  Text(
                    thankYouMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                ],

                if (receiptFooter.isNotEmpty) ...[
                  Text(
                    receiptFooter,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                ],

                const Text(
                  '*** POWERED BY CAFE POS ***',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.black38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens WhatsApp with the customer's number and this bill typed in.
  /// Asks for the number if the order has none (or an invalid one).
  Future<void> _sendOnWhatsApp(BuildContext context) async {
    var number = normalizeWhatsAppNumber((orderData['customerPhone'] ?? '').toString());
    if (number == null) {
      final ctrl = TextEditingController(text: (orderData['customerPhone'] ?? '').toString());
      final entered = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send bill on WhatsApp'),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(
                labelText: 'Customer mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: '10-digit mobile',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Open WhatsApp')),
          ],
        ),
      );
      if (entered == null) return;
      number = normalizeWhatsAppNumber(entered);
      if (number == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid 10-digit mobile number.')));
        }
        return;
      }
    }
    final text = buildWhatsAppBill(order: orderData, orderId: orderId, settings: businessSettings);
    final ok = await launchUrl(whatsAppUri(number, text), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
    }
  }

  Widget _buildDottedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.black45)),
            );
          }),
        );
      },
    );
  }
}
