import 'package:cloud_firestore/cloud_firestore.dart';

import 'bill_numbers.dart';

import 'bill.dart';

/// Read-only view of an order document (fields exactly as stored).
class PosOrder {
  PosOrder(this.id, this.data);

  factory PosOrder.fromDoc(DocumentSnapshot doc) =>
      PosOrder(doc.id, Map<String, dynamic>.from((doc.data() as Map?) ?? const {}));

  final String id;
  final Map<String, dynamic> data;

  String get customerName => (data['customerName'] ?? '').toString();
  String get customerPhone => (data['customerPhone'] ?? '').toString();
  String get tableNo => (data['tableNo'] ?? '').toString();
  String get orderType => (data['orderType'] ?? 'Dine-In').toString();
  String get specialRequest => (data['specialRequest'] ?? '').toString();

  /// pending | preparing | ready | completed | cancelled
  String get status => (data['status'] ?? 'pending').toString().toLowerCase();
  String get paymentStatus => (data['paymentStatus'] ?? 'pending').toString().toLowerCase();
  bool get isPaid => isPaidStatus(paymentStatus);
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => !isCompleted && !isCancelled;
  bool get isVirtualTable => data['isVirtualTable'] == true;
  bool get hasNewItemsAdded => data['hasNewItemsAdded'] == true;

  List<Map<String, dynamic>> get items =>
      ((data['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  int get itemCount => items.fold(0, (n, i) => n + ((i['qty'] ?? 1) as num).toInt());

  double get totalPrice => ((data['totalPrice'] ?? 0) as num).toDouble();
  double get subtotal => ((data['subtotal'] ?? data['totalPrice'] ?? 0) as num).toDouble();
  double get discount => ((data['discountGiven'] ?? 0) as num).toDouble();
  bool get hasGst => data['hasGst'] == true;
  double get gstAmount => hasGst ? (totalPrice - (subtotal - discount)).clamp(0, double.infinity).toDouble() : 0;

  DateTime? get createdAt => (data['createdAt'] as Timestamp?)?.toDate();
  DateTime? get completedAt => (data['completedAt'] as Timestamp?)?.toDate();
  DateTime? get paidAt => (data['paidAt'] as Timestamp?)?.toDate();

  // ---- Takeaway ----
  bool get isTakeaway => orderType.toLowerCase().contains('takeaway');

  /// Daily token number for takeaway orders (null for dine-in/old orders).
  int? get tokenNo => (data['tokenNo'] as num?)?.toInt();

  /// When the customer was promised the order (null = as soon as possible).
  DateTime? get pickupAt => (data['pickupAt'] as Timestamp?)?.toDate();

  /// "Token #12" or, without a token, the bill number.
  String get tokenLabel => tokenNo != null ? 'Token #$tokenNo' : billNo;

  /// Takeaway customer name ("Walk-in" when none was given).
  String get takeawayName {
    final n = customerName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
    return n.isEmpty || n == 'Counter Customer' ? 'Walk-in' : n;
  }

  /// Short bill number, same as receipts: first 6 chars of the id.
  /// Sequential bill number (e.g. 26-27/0042); old orders keep #ABCDEF.
  String get billNo => displayBillNo(data, id);

  String get paymentLabel {
    final m = methodFromStatus(paymentStatus);
    if (m != null) return m.label;
    return isPaid ? 'Paid' : 'Unpaid';
  }

  /// "Rahul (Table 4)" style label used across the app (unchanged logic).
  String get displayName => isTakeaway && tableNo.isEmpty && tokenNo != null
      ? '$takeawayName (Token #$tokenNo)'
      : formatCustomerDisplayName(customerName, tableNo.isEmpty ? null : tableNo);

  /// Kitchen-facing status label.
  String get statusLabel => switch (status) {
        'preparing' => 'Preparing',
        'ready' => 'Ready',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => 'Ordered',
      };
}

/// Cleans "(Table 4)" from names and joins table/customer (original logic).
String formatCustomerDisplayName(String rawName, String? tableNo) {
  final clean = rawName
      .replaceAll(r'$1', '')
      .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  var t = (tableNo ?? '').trim();
  if (t.isNotEmpty && !t.toLowerCase().startsWith('table')) t = 'Table $t';

  if (clean.isNotEmpty && t.isNotEmpty) return '$clean ($t)';
  if (clean.isNotEmpty) return clean;
  if (t.isNotEmpty) return t;
  return 'Counter Customer';
}

/// Orders created since local midnight.
List<PosOrder> todaysOrders(Iterable<PosOrder> all, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final start = DateTime(n.year, n.month, n.day);
  return all.where((o) => o.createdAt != null && o.createdAt!.isAfter(start)).toList();
}

/// Result of placing today's active orders on numbered and virtual tables.
class TableBoard {
  TableBoard(this.byTable, this.virtuals);
  final Map<int, PosOrder> byTable;
  final List<PosOrder> virtuals;

  /// Same matching rules as the original Orders screen.
  static TableBoard build(List<PosOrder> today, int tableCount) {
    final byTable = <int, PosOrder>{};
    final virtuals = <PosOrder>[];
    for (final o in today) {
      if (o.isCompleted || o.isCancelled) continue;
      if (o.isTakeaway && o.tableNo.trim().isEmpty) continue; // shown on the Takeaway board
      final customer = o.customerName.toLowerCase();
      final tNo = o.tableNo.trim();
      final explicitVirtual =
          o.isVirtualTable || tNo.toLowerCase().startsWith('v-') || tNo.toLowerCase().startsWith('virtual');

      var matched = false;
      if (!explicitVirtual) {
        for (var i = 1; i <= tableCount; i++) {
          if (customer.contains('table $i') || customer.contains('t$i') || tNo == '$i' || tNo.toLowerCase() == 'table $i') {
            byTable[i] = o;
            matched = true;
            break;
          }
        }
      }
      if (!matched && tNo.isNotEmpty) virtuals.add(o);
    }
    return TableBoard(byTable, virtuals);
  }
}
