import 'package:cloud_firestore/cloud_firestore.dart';

import '../orders/order_model.dart';

/// CSV exports, ported unchanged from the original Reports screen so the
/// files have the same columns and numbers.

String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
String fileDate(DateTime d) => _d(d);

DateTime? _created(PosOrder o) => (o.data['createdAt'] as Timestamp?)?.toDate();

String salesCsv(List<PosOrder> all, DateTime start, DateTime end) {
  final rangeDocs = all.where((o) {
    final dt = _created(o);
    if (dt == null) return false;
    return dt.isAfter(start.subtract(const Duration(seconds: 1))) && dt.isBefore(end.add(const Duration(seconds: 1)));
  });
  final csv = StringBuffer()
    ..writeln('Bill No,Date,Time,Table No,Customer Name,Phone,Item Count,Subtotal,GST,Discount,Grand Total,Payment Status,Order Status');
  for (final o in rangeDocs) {
    final d = o.data;
    final billNo = '#${o.id.substring(0, o.id.length > 5 ? 5 : o.id.length).toUpperCase()}';
    final dt = _created(o) ?? DateTime.now();
    final dateStr = '${dt.day}-${dt.month}-${dt.year}';
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final table = (d['tableNo'] ?? d['orderType'] ?? 'Dine-In').toString().replaceAll(',', ' ');
    final name = (d['customerName'] ?? 'Guest').toString().replaceAll(',', ' ');
    final phone = (d['customerPhone'] ?? '').toString();
    final items = (d['items'] as List?) ?? const [];
    final subtotal = ((d['subtotal'] ?? d['totalPrice'] ?? 0.0) as num).toDouble();
    final total = ((d['totalPrice'] ?? 0.0) as num).toDouble();
    final discount = ((d['discountGiven'] ?? 0.0) as num).toDouble();
    // GST = total − (subtotal − discount); identical to before when no discount.
    final gst = (d['hasGst'] == true) ? (total - (subtotal - discount)) : 0.0;
    final payStatus = (d['paymentStatus'] ?? 'pending').toString().toUpperCase();
    final status = (d['status'] ?? 'completed').toString().toUpperCase();
    csv.writeln('"$billNo","$dateStr","$timeStr","$table","$name","$phone",${items.length},$subtotal,$gst,$discount,$total,"$payStatus","$status"');
  }
  return csv.toString();
}

String customersCsv(List<PosOrder> all, DateTime start, DateTime end) {
  final custMap = <String, Map<String, dynamic>>{};
  for (final o in all) {
    final dt = _created(o);
    if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;
    final phone = o.customerPhone.trim();
    final name = (o.data['customerName'] ?? 'Guest').toString().trim().replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
    final key = phone.isNotEmpty ? phone : name.toLowerCase();
    final price = o.totalPrice;
    final c = custMap[key];
    if (c == null) {
      custMap[key] = {'name': name.isEmpty ? 'Guest' : name, 'phone': phone, 'totalOrders': 1, 'totalSpent': price, 'lastVisit': dt};
    } else {
      c['totalOrders'] = (c['totalOrders'] as int) + 1;
      c['totalSpent'] = (c['totalSpent'] as double) + price;
      if (dt.isAfter(c['lastVisit'] as DateTime)) c['lastVisit'] = dt;
    }
  }
  final csv = StringBuffer()..writeln('Customer Name,Mobile Number,Orders Placed,Total Spent (Rs),Average Order Value (Rs),Last Visit Date');
  for (final c in custMap.values) {
    final orders = c['totalOrders'] as int;
    final spent = c['totalSpent'] as double;
    final avg = orders > 0 ? spent / orders : 0.0;
    final lv = c['lastVisit'] as DateTime;
    csv.writeln('"${c['name'].toString().replaceAll(',', ' ')}","${c['phone']}",$orders,$spent,${avg.toStringAsFixed(2)},"${lv.day}-${lv.month}-${lv.year}"');
  }
  return csv.toString();
}

String itemsCsv(List<PosOrder> all, DateTime start, DateTime end) {
  final itemMap = <String, Map<String, dynamic>>{};
  double totalRev = 0;
  for (final o in all) {
    final dt = _created(o);
    if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;
    for (final it in o.items) {
      final name = (it['name'] ?? 'Item').toString().replaceAll(',', ' ');
      final size = (it['size'] ?? 'Regular').toString();
      final key = '$name ($size)';
      final qty = ((it['qty'] ?? 1) as num).toInt();
      final price = ((it['price'] ?? 0.0) as num).toDouble();
      final rev = qty * price;
      totalRev += rev;
      final m = itemMap[key];
      if (m == null) {
        itemMap[key] = {'name': name, 'size': size, 'qty': qty, 'price': price, 'revenue': rev};
      } else {
        m['qty'] = (m['qty'] as int) + qty;
        m['revenue'] = (m['revenue'] as double) + rev;
      }
    }
  }
  final csv = StringBuffer()..writeln('Item Name,Variant / Size,Quantity Sold,Unit Price (Rs),Total Revenue (Rs),Revenue Contribution (%)');
  for (final it in itemMap.values) {
    final rev = it['revenue'] as double;
    final contrib = totalRev > 0 ? rev / totalRev * 100 : 0.0;
    csv.writeln('"${it['name']}","${it['size']}",${it['qty']},${it['price']},$rev,${contrib.toStringAsFixed(2)}%');
  }
  return csv.toString();
}
