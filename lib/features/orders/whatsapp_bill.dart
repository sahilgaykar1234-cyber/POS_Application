import 'package:cloud_firestore/cloud_firestore.dart';

import 'bill_numbers.dart';

/// Sending a bill on WhatsApp the free way: we open WhatsApp (app or web)
/// with the customer's number and the bill already typed; staff tap Send.
/// No WhatsApp Business API, no cost, nothing sent automatically.

/// 10-digit Indian mobile → "91XXXXXXXXXX"; already-international numbers
/// are kept. Returns null if it doesn't look like a mobile number.
String? normalizeWhatsAppNumber(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 10) return '91$d';
  if (d.length == 11 && d.startsWith('0')) return '91${d.substring(1)}';
  if (d.length == 12 && d.startsWith('91')) return d;
  if (d.length >= 11 && d.length <= 15) return d;
  return null;
}

String _money(num v) {
  final d = v.toDouble();
  return d == d.roundToDouble() ? '₹${d.toInt()}' : '₹${d.toStringAsFixed(2)}';
}

/// Plain-text bill (WhatsApp *bold* formatting) from the stored order.
String buildWhatsAppBill({
  required Map<String, dynamic> order,
  required String orderId,
  Map<String, dynamic>? settings,
}) {
  final shop = (settings?['shopName'] ?? '').toString().trim();
  final billNo = displayBillNo(order, orderId);
  final ts = (order['completedAt'] ?? order['paidAt'] ?? order['createdAt']);
  final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';

  final items = ((order['items'] as List?) ?? const []).whereType<Map>().toList();
  final subtotal = ((order['subtotal'] ?? order['totalPrice'] ?? 0) as num).toDouble();
  final total = ((order['totalPrice'] ?? subtotal) as num).toDouble();
  final discount = ((order['discountGiven'] ?? 0) as num).toDouble();
  final gst = order['hasGst'] == true ? (total - (subtotal - discount)).clamp(0, double.infinity) : 0.0;
  final gstPct = order['gstPercentage'];
  final status = (order['paymentStatus'] ?? '').toString();
  final paidVia = status.startsWith('paid_') ? status.substring(5).toUpperCase() : (status.startsWith('paid') ? 'PAID' : '');

  final b = StringBuffer();
  if (shop.isNotEmpty) b.writeln('*$shop*');
  b.writeln('Bill $billNo · $date');
  final table = (order['tableNo'] ?? '').toString().trim();
  if (table.isNotEmpty) b.writeln(table.toLowerCase().startsWith('table') ? table : 'Table $table');
  b.writeln();
  for (final it in items) {
    final qty = ((it['qty'] ?? 1) as num).toInt();
    final price = ((it['price'] ?? 0) as num).toDouble();
    final size = (it['size'] ?? 'Standard').toString();
    b.writeln('$qty × ${it['name']}${size != 'Standard' ? ' ($size)' : ''} — ${_money(price * qty)}');
  }
  b.writeln();
  b.writeln('Subtotal: ${_money(subtotal)}');
  if (discount > 0) b.writeln('Discount: -${_money(discount)}');
  if (gst > 0) b.writeln('GST${gstPct != null ? ' $gstPct%' : ''}: ${_money(gst)}');
  b.writeln('*Total: ${_money(total)}*');
  if (paidVia.isNotEmpty) b.writeln('Paid via $paidVia');
  final thanks = (settings?['thankYouMessage'] ?? '').toString().trim();
  b.writeln();
  b.write(thanks.isEmpty ? 'Thank you! Visit again.' : thanks);
  return b.toString();
}

/// `https://wa.me/<number>?text=<bill>` (universal fallback).
Uri whatsAppUri(String number, String text) =>
    Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');

/// The link that opens the chat directly, with no "open app?" landing page:
///  - phones/tablets (Android, iOS): the WhatsApp app (`whatsapp://send`)
///  - computers: WhatsApp Web (`web.whatsapp.com/send`)
Uri whatsAppDirectUri(String number, String text, {required bool mobile}) {
  final t = Uri.encodeComponent(text);
  return mobile
      ? Uri.parse('whatsapp://send?phone=$number&text=$t')
      : Uri.parse('https://web.whatsapp.com/send?phone=$number&text=$t');
}

/// "Your order is ready" message for takeaway customers.
String buildReadyMessage({required String shopName, required String customerName, int? token, required String billNo}) {
  final who = customerName.trim().isEmpty || customerName == 'Walk-in' ? '' : ' $customerName';
  final ref = token != null ? 'Token #$token' : 'order $billNo';
  final at = shopName.trim().isEmpty ? '' : ' at *${shopName.trim()}*';
  return 'Hi$who, your takeaway ($ref) is *ready for pickup*$at. See you soon!';
}
