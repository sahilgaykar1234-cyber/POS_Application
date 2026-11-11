import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/data/firestore_paths.dart';
import 'bill.dart';
import 'order_model.dart';

/// Customer details as entered at the POS, normalised exactly like the
/// original form did (handles name/phone typed in the wrong box).
class CustomerInput {
  CustomerInput({required this.name, required this.phone});
  final String name;
  final String phone;

  static CustomerInput normalize(String rawName, String rawPhone) {
    rawName = rawName.trim();
    rawPhone = rawPhone.trim();
    final digitsInName = rawName.replaceAll(RegExp(r'\D'), '');
    final digitsInPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
    var name = rawName;
    var phone = rawPhone;
    if (digitsInName.length >= 10 && RegExp(r'[a-zA-Z]').hasMatch(rawPhone)) {
      name = rawPhone;
      phone = digitsInName;
    } else if (digitsInPhone.length >= 10) {
      phone = digitsInPhone;
    }
    return CustomerInput(name: name, phone: phone);
  }
}

/// Returning customer found by phone number.
class KnownCustomer {
  KnownCustomer(this.name, this.lastItems, this.lastVisit);
  final String name;
  final List<Map<String, dynamic>> lastItems;
  final DateTime? lastVisit;
}

/// All order writes for the signed-in cafe. Field names and values match the
/// original app, so old and new orders read the same everywhere.
class OrderService {
  OrderService._();
  static final instance = OrderService._();

  CollectionReference<Map<String, dynamic>> get _orders => FirestorePaths.orders();

  Stream<List<PosOrder>> watchAll() =>
      _orders.snapshots().map((s) => s.docs.map(PosOrder.fromDoc).toList());

  Stream<PosOrder?> watchOne(String id) =>
      _orders.doc(id).snapshots().map((d) => d.exists ? PosOrder.fromDoc(d) : null);

  /// Places a new order or updates [existing].
  ///
  /// New takeaway orders get the next daily token number (atomically, so two
  /// devices never share a token) and an optional promised pickup time.
  Future<({String id, int? token})> saveOrder({
    PosOrder? existing,
    required String tableNo,
    required String rawName,
    required String rawPhone,
    required String orderType,
    required String note,
    required List<Map<String, dynamic>> cart,
    required bool gstEnabled,
    required double gstPercent,
    String? createdByRole,
    int? pickupInMinutes,
    bool assignToken = true,
  }) async {
    final c = CustomerInput.normalize(rawName, rawPhone);
    final displayName = formatCustomerDisplayName(c.name, tableNo.trim());
    final bill = Bill.compute(items: cart, gstEnabled: gstEnabled, gstPercent: gstPercent);

    if (existing == null) {
      final initialItems = cart.map((e) => {...e, 'isDone': false}).toList();
      final isTakeaway = orderType.toLowerCase().contains('takeaway');
      final data = <String, dynamic>{
        'deviceId': 'counter_manager_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': displayName,
        'tableNo': tableNo.trim(),
        'customerPhone': c.phone,
        'orderType': orderType,
        'specialRequest': note.trim(),
        'items': initialItems,
        'totalPrice': bill.total,
        'subtotal': bill.subtotal,
        'hasGst': gstEnabled,
        'gstPercentage': gstPercent,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'paymentStatus': 'pending',
        'hasNewItemsAdded': false,
        'createdByRole': ?createdByRole,
        'createdAt': FieldValue.serverTimestamp(),
        if (isTakeaway && pickupInMinutes != null)
          'pickupAt': Timestamp.fromDate(DateTime.now().add(Duration(minutes: pickupInMinutes))),
      };

      if (isTakeaway && assignToken) {
        final ref = _orders.doc();
        final counter = FirestorePaths.cafeCounter('takeaway_${takeawayDayKey(DateTime.now())}');
        try {
          final token = await FirebaseFirestore.instance.runTransaction<int>((tx) async {
            final snap = await tx.get(counter);
            final next = (snap.data()?['next'] as num?)?.toInt() ?? 1;
            tx.set(counter, {'next': next + 1, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
            tx.set(ref, {...data, 'tokenNo': next});
            return next;
          });
          return (id: ref.id, token: token);
        } catch (_) {
          // Offline / transaction failed: never lose the order — save it
          // without a token (the bill number is shown instead).
          await ref.set(data);
          return (id: ref.id, token: null);
        }
      }

      final ref = await _orders.add(data);
      return (id: ref.id, token: null);
    }

    final hasAnyNew = cart.any((e) => (e['isDone'] ?? false) == false);
    await _orders.doc(existing.id).update({
      'customerName': displayName,
      'tableNo': tableNo.trim(),
      'customerPhone': c.phone,
      'orderType': orderType,
      'specialRequest': note.trim(),
      'items': cart,
      'totalPrice': bill.total,
      'subtotal': bill.subtotal,
      'hasGst': gstEnabled,
      'gstPercentage': gstPercent,
      'status': 'pending',
      'kitchenStatus': 'pending',
      'hasNewItemsAdded': hasAnyNew,
      // Items changed: any earlier discount must be re-applied at settle time.
      'discountType': FieldValue.delete(),
      'discountValue': FieldValue.delete(),
      'discountGiven': FieldValue.delete(),
    });
    return (id: existing.id, token: existing.tokenNo);
  }

  Future<void> setStatus(String id, String status) =>
      _orders.doc(id).update({'status': status, 'kitchenStatus': status});

  /// Records payment (and optionally completes the order / frees the table).
  /// Applies the discount and recomputes the total with [Bill.compute].
  Future<Map<String, dynamic>> settle({
    required PosOrder order,
    required PaymentMethod method,
    required DiscountType discountType,
    required double discountValue,
    required double? cashReceived,
    required bool complete,
  }) async {
    final bill = Bill.compute(
      items: order.items,
      gstEnabled: order.hasGst,
      gstPercent: ((order.data['gstPercentage'] ?? 5) as num).toDouble(),
      discountType: discountType,
      discountValue: discountValue,
    );
    final update = <String, dynamic>{
      'subtotal': bill.subtotal,
      'totalPrice': bill.total,
      'discountType': discountType == DiscountType.none ? FieldValue.delete() : discountType.name,
      'discountValue': discountType == DiscountType.none ? FieldValue.delete() : discountValue,
      'discountGiven': bill.discount > 0 ? bill.discount : FieldValue.delete(),
      'paymentStatus': method.status,
      'paymentMethod': method.name,
      'paidAt': FieldValue.serverTimestamp(),
      'cashReceived': method == PaymentMethod.cash && cashReceived != null ? cashReceived : FieldValue.delete(),
      'changeReturned': method == PaymentMethod.cash && cashReceived != null
          ? (cashReceived - bill.total).clamp(0, double.infinity)
          : FieldValue.delete(),
    };
    if (complete) {
      update['status'] = 'completed';
      update['kitchenStatus'] = 'completed';
      update['completedAt'] = FieldValue.serverTimestamp();
    }
    await _orders.doc(order.id).update(update);
    final fresh = await _orders.doc(order.id).get();
    return fresh.data() ?? {};
  }

  /// Frees the table without changing payment (original "Done" action).
  Future<Map<String, dynamic>> complete(String id) async {
    await _orders.doc(id).update({
      'status': 'completed',
      'kitchenStatus': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    final fresh = await _orders.doc(id).get();
    return fresh.data() ?? {};
  }

  Future<void> delete(String id) => _orders.doc(id).delete();

  /// Finds the last name and items for a 10-digit phone (original logic).
  Future<KnownCustomer?> lookupByPhone(String rawPhone) async {
    final phone = rawPhone.trim().replaceAll(RegExp(r'\D'), '');
    if (phone.length != 10) return null;
    final snap = await _orders.where('customerPhone', isEqualTo: phone).get();
    if (snap.docs.isEmpty) return null;

    final docs = snap.docs.toList()
      ..sort((a, b) {
        final tA = a.data()['createdAt'] as Timestamp?;
        final tB = b.data()['createdAt'] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tB.compareTo(tA);
      });

    var validName = '';
    for (final d in docs) {
      final c = (d.data()['customerName'] ?? '')
          .toString()
          .replaceAll(r'$1', '')
          .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
          .trim();
      if (c.isNotEmpty && !RegExp(r'^\d+$').hasMatch(c) && c.toLowerCase() != 'guest' && !c.toLowerCase().startsWith('table')) {
        validName = c;
        break;
      }
    }
    if (validName.isEmpty) return null;
    final last = docs.first.data();
    final items = ((last['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return KnownCustomer(validName, items, (last['createdAt'] as Timestamp?)?.toDate());
  }
}

/// yyyymmdd (local day) — token numbers restart every day.
String takeawayDayKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
