import 'package:cloud_firestore/cloud_firestore.dart';

import '../orders/bill_numbers.dart';

/// Everything a receipt shows, taken ONLY from the saved order (prices,
/// totals, tax, discount, payment) plus the cafe's details from Settings.
/// Nothing is recalculated from today's menu or today's tax settings, so an
/// old bill always prints exactly as it was charged. Pure (unit-tested).
class ReceiptData {
  ReceiptData._({
    required this.orderId,
    required this.shopName,
    required this.tagline,
    required this.address,
    required this.phone,
    required this.gstNumber,
    required this.logoBase64,
    required this.header,
    required this.footer,
    required this.thanks,
    required this.billNo,
    required this.orderRef,
    required this.createdAt,
    required this.paidAt,
    required this.tableNo,
    required this.orderType,
    required this.token,
    required this.customerName,
    required this.customerPhone,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.gstPercent,
    required this.gst,
    required this.total,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.cashReceived,
    required this.changeReturned,
    required this.orderStatus,
    required this.takenBy,
  });

  final String orderId;

  // Cafe (from Settings; empty when not filled in – never invented).
  final String shopName;
  final String tagline;
  final String address;
  final String phone;
  final String gstNumber;
  final String? logoBase64;
  final String header;
  final String footer;
  final String thanks;

  // Order.
  final String billNo;

  /// Short unique reference of the saved order, e.g. "#KB87XO".
  final String orderRef;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final String tableNo;
  final String orderType;
  final int? token;
  final String customerName;
  final String customerPhone;
  final List<ReceiptLine> lines;
  final String orderStatus;
  final String takenBy;

  // Money (as saved).
  final double subtotal;
  final double discount;
  final double? gstPercent; // null = no GST on this bill
  final double gst;
  final double total;

  // Payment.
  final String paymentStatus; // raw, e.g. "paid_upi" / "pending"
  final String paymentMethod; // "Cash" / "UPI" / "Card" / ""
  final double? cashReceived;
  final double? changeReturned;

  bool get isPaid => paymentStatus.startsWith('paid');
  bool get hasGst => gstPercent != null && gst > 0;
  double get taxable => subtotal - discount;
  double get cgst => gst / 2;
  double get sgst => gst - cgst;
  int get itemCount => lines.fold(0, (n, l) => n + l.qty);
  bool get isTakeaway => orderType.toLowerCase().contains('takeaway');

  /// When the bill was settled (or created, for unpaid bills).
  DateTime? get billTime => paidAt ?? createdAt;

  String get paymentLabel => isPaid ? (paymentMethod.isEmpty ? 'Paid' : 'Paid · $paymentMethod') : 'Payment pending';

  String get statusLabel => switch (orderStatus) {
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'ready' => 'Ready',
        'preparing' => 'Preparing',
        _ => 'Ordered',
      };

  /// "Table 4" / "Takeaway · Token #12" / "Takeaway".
  String get whereLabel {
    if (tableNo.trim().isNotEmpty) {
      final t = tableNo.trim();
      return t.toLowerCase().startsWith('table') ? t : 'Table $t';
    }
    if (isTakeaway) return token != null ? 'Takeaway · Token #$token' : 'Takeaway';
    return orderType;
  }

  static ReceiptData from(Map<String, dynamic> order, String orderId, [Map<String, dynamic>? settings]) {
    String s(Object? v) => (v ?? '').toString().trim();
    double n(Object? v) => v is num ? v.toDouble() : (double.tryParse(s(v)) ?? 0);
    double? nOrNull(Object? v) => v is num ? v.toDouble() : double.tryParse(s(v));
    DateTime? t(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

    final lines = <ReceiptLine>[
      for (final it in ((order['items'] as List?) ?? const []).whereType<Map>())
        ReceiptLine(
          name: s(it['name']),
          variant: s(it['size']) == 'Standard' ? '' : s(it['size']),
          qty: (it['qty'] is num ? (it['qty'] as num).toInt() : int.tryParse(s(it['qty'])) ?? 1),
          unitPrice: n(it['price']),
          extra: it['custom'] == true,
        ),
    ];
    final linesTotal = lines.fold<double>(0, (t, l) => t + l.amount);
    final subtotal = order['subtotal'] is num ? n(order['subtotal']) : linesTotal;
    final total = order['totalPrice'] is num ? n(order['totalPrice']) : subtotal;
    final discount = n(order['discountGiven']);
    final hasGst = order['hasGst'] == true;
    final gst = hasGst ? (total - (subtotal - discount)).clamp(0, double.infinity).toDouble() : 0.0;

    final pay = s(order['paymentStatus']).toLowerCase();
    final method = pay.startsWith('paid_') ? pay.substring(5) : s(order['paymentMethod']).toLowerCase();
    final methodLabel = switch (method) {
      'upi' => 'UPI',
      'cash' => 'Cash',
      'card' => 'Card',
      '' => '',
      _ => method[0].toUpperCase() + method.substring(1),
    };

    final rawName = s(order['customerName']).replaceAll(RegExp(r'\s*\((Table|Token)[^)]*\)', caseSensitive: false), '').trim();
    final name = RegExp(r'^table\s*\d+$', caseSensitive: false).hasMatch(rawName) ? '' : rawName;

    return ReceiptData._(
      orderId: orderId,
      shopName: s(settings?['shopName']),
      tagline: s(settings?['tagline']),
      address: s(settings?['address']),
      phone: s(settings?['mobileNumber']),
      gstNumber: s(settings?['gstNumber']),
      logoBase64: (settings?['shopLogoBase64'] is String && s(settings?['shopLogoBase64']).isNotEmpty) ? settings!['shopLogoBase64'] as String : null,
      header: s(settings?['receiptHeader']),
      footer: s(settings?['receiptFooter']),
      thanks: s(settings?['thankYouMessage']),
      billNo: displayBillNo(order, orderId),
      orderRef: orderId.isEmpty ? '' : '#${orderId.substring(0, orderId.length < 6 ? orderId.length : 6).toUpperCase()}',
      createdAt: t(order['createdAt']),
      paidAt: t(order['paidAt']) ?? (pay.startsWith('paid') ? t(order['completedAt']) : null),
      tableNo: s(order['tableNo']),
      orderType: s(order['orderType']).isEmpty ? 'Dine-In' : s(order['orderType']),
      token: order['tokenNo'] is num ? (order['tokenNo'] as num).toInt() : null,
      customerName: name,
      customerPhone: s(order['customerPhone']),
      lines: lines,
      subtotal: subtotal,
      discount: discount,
      gstPercent: hasGst ? (nOrNull(order['gstPercentage']) ?? 0) : null,
      gst: gst,
      total: total,
      paymentStatus: pay.isEmpty ? 'pending' : pay,
      paymentMethod: methodLabel,
      cashReceived: order['cashReceived'] is num ? n(order['cashReceived']) : null,
      changeReturned: order['changeReturned'] is num ? n(order['changeReturned']) : null,
      orderStatus: s(order['status']).toLowerCase(),
      takenBy: s(order['createdByRole']),
    );
  }
}

class ReceiptLine {
  const ReceiptLine({required this.name, required this.variant, required this.qty, required this.unitPrice, this.extra = false});
  final String name;
  final String variant;
  final int qty;
  final double unitPrice;
  final bool extra;
  double get amount => unitPrice * qty;
}

/// ₹1,234 / ₹1,234.50 (Indian grouping).
String receiptMoney(num v, {bool always2 = false}) {
  final neg = v < 0;
  final d = v.abs().toDouble();
  final whole = d.truncate();
  final paise = ((d - whole) * 100).round();
  var w = whole.toString();
  if (w.length > 3) {
    final last3 = w.substring(w.length - 3);
    var rest = w.substring(0, w.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    w = '${parts.join(',')},$last3';
  }
  final p = (paise == 0 && !always2) ? '' : '.${paise.toString().padLeft(2, '0')}';
  return '${neg ? '−' : ''}₹$w$p';
}

String receiptDate(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}
