import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentCompleteReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderId;
  final Map<String, dynamic>? businessSettings;

  const PaymentCompleteReceiptScreen({
    super.key,
    required this.orderData,
    required this.orderId,
    this.businessSettings,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Fetch dynamic settings from businessSettings or Fallback
    final String? shopLogoBase64 = businessSettings?['shopLogoBase64'];
    final String shopName = (businessSettings?['shopName'] ?? 'Pizza La Forno').toString();
    final String tagline = (businessSettings?['tagline'] ?? 'Wood Fired Pizza').toString();
    final String address = (businessSettings?['address'] ?? '').toString();
    final String mobileNumber = (businessSettings?['mobileNumber'] ?? '').toString();
    final String gstNumber = (businessSettings?['gstNumber'] ?? '').toString();
    
    final String receiptHeader = (businessSettings?['receiptHeader'] ?? 'Thank you for your order!').toString();
    final String receiptFooter = (businessSettings?['receiptFooter'] ?? 'Visit Again!').toString();
    final String thankYouMessage = (businessSettings?['thankYouMessage'] ?? 'Thank You!').toString();

    final bool showGst = businessSettings?['showGst'] == true || orderData['hasGst'] == true;
    final double gstPercentage = double.tryParse((businessSettings?['gstPercentage'] ?? orderData['gstPercentage'] ?? '5').toString()) ?? 5.0;

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
    final double taxAmount = showGst ? (grandTotal - subtotal > 0 ? grandTotal - subtotal : subtotal * (gstPercentage / 100.0)) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A431D),
        elevation: 0,
        title: const Text('Thermal Bill Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded, color: Colors.white),
            tooltip: 'Print Receipt',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sending print job to 80mm thermal printer...'), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Container(
            width: 380, // Standard 80mm Thermal paper width preview
            padding: const EdgeInsets.all(22.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
              ],
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
                              return Image.asset('assets/images/logo.png', fit: BoxFit.contain);
                            },
                          )
                        : Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.black12,
                                child: const Icon(Icons.local_pizza_rounded, color: Color(0xFF7A431D), size: 36),
                              );
                            },
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bill: $billNo', style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black)),
                    Text('$dateStr $timeStr', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tableNo.isNotEmpty ? (tableNo.toLowerCase().contains('table') ? tableNo : 'Table $tableNo') : 'Counter / Takeaway',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    Text('Mode: $paymentMode', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                  ],
                ),
                if (customerName.isNotEmpty && customerName.toLowerCase() != 'walk-in guest') ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Customer: $customerName', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87)),
                      if (customerPhone.isNotEmpty)
                        Text(customerPhone, style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Colors.black54)),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                // 🟢 2. ITEMS TABLE (QTY, ITEM NAME, PRICE)
                Row(
                  children: const [
                    Expanded(flex: 5, child: Text('ITEM', style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black))),
                    Expanded(flex: 2, child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black))),
                    Expanded(flex: 3, child: Text('AMOUNT', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black))),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87)),
                    Text('₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black)),
                  ],
                ),

                if (showGst) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GST ($gstPercentage%):', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87)),
                      Text('₹${taxAmount.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black)),
                    ],
                  ),
                ],

                const SizedBox(height: 6),
                _buildDottedDivider(),
                const SizedBox(height: 6),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  '*** SOFTWARE POWERED BY POS APP ***',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.black38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black45),
              ),
            );
          }),
        );
      },
    );
  }
}