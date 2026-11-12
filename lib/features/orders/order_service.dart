import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/data/firestore_paths.dart';
import 'bill.dart';
import 'bill_numbers.dart';
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
  Future<({String id, int? token, String? billNo})> saveOrder({
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
    bool assignBillNumber = true,
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

      final wantToken = isTakeaway && assignToken;
      final ref = _orders.doc();
      if (!wantToken && !assignBillNumber) {
        await ref.set(data);
        return (id: ref.id, token: null, billNo: null);
      }
      final now = DateTime.now();
      try {
        // Only needed the very first time (no counter yet this year).
        final seed = assignBillNumber ? await _billSeed(now) : null;
        // One transaction: next bill number in the cafe's series (and the
        // next daily takeaway token), so two devices never share a number.
        // Both counters are read together: one round trip, then one commit.
        final r = await FirebaseFirestore.instance.runTransaction<({int? token, String? billNo})>((tx) async {
          final billRef = FirestorePaths.cafeCounter(billCounterName(now));
          final tokenRef = FirestorePaths.cafeCounter('takeaway_${takeawayDayKey(now)}');
          // All reads must come before writes in a transaction.
          final reads = await Future.wait([
            if (assignBillNumber) tx.get(billRef),
            if (wantToken) tx.get(tokenRef),
          ]);
          final billSnap = assignBillNumber ? reads.first : null;
          final tokenSnap = wantToken ? reads.last : null;
          final seq = billSnap == null ? null : _takeBillSeq(tx, billRef, billSnap, seed!);
          final extra = <String, dynamic>{};
          String? billNo;
          int? token;
          if (seq != null) {
            billNo = formatBillNumber(now, seq);
            extra.addAll(_billFields(now, seq));
          }
          if (tokenSnap != null) {
            token = (tokenSnap.data()?['next'] as num?)?.toInt() ?? 1;
            tx.set(tokenRef, {'next': token + 1, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
            extra['tokenNo'] = token;
          }
          tx.set(ref, {...data, ...extra});
          return (token: token, billNo: billNo);
        });
        return (id: ref.id, token: r.token, billNo: r.billNo);
      } catch (e) {
        debugPrint('Bill number / token not assigned: $e');
        // Offline / transaction failed: never lose the order. It is saved
        // without numbers; the bill number is given when it is settled.
        await ref.set(data);
        return (id: ref.id, token: null, billNo: null);
      }
    }

    final hasAnyNew = cart.any((e) => (e['isDone'] ?? false) == false);
    if (existing.isCompleted) {
      // Correcting a closed bill: keep it closed and paid as it was, keep its
      // discount, nothing goes to the kitchen.
      await _orders.doc(existing.id).update({
        'customerName': displayName,
        'tableNo': tableNo.trim(),
        'customerPhone': c.phone,
        'orderType': orderType,
        'specialRequest': note.trim(),
        ..._recalc(existing, [for (final e in cart) {...e, 'isDone': true}]),
        'editedAt': FieldValue.serverTimestamp(),
      });
      return (id: existing.id, token: existing.tokenNo, billNo: existing.data['billNo'] as String?);
    }
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
      // Only new (unsent) items send the order back to the kitchen.
      'status': statusAfterEdit(existing.status, hasNewItems: hasAnyNew),
      'kitchenStatus': statusAfterEdit(existing.status, hasNewItems: hasAnyNew),
      'hasNewItemsAdded': hasAnyNew,
      // Items changed: any earlier discount must be re-applied at settle time.
      'discountType': FieldValue.delete(),
      'discountValue': FieldValue.delete(),
      'discountGiven': FieldValue.delete(),
    });
    return (id: existing.id, token: existing.tokenNo, billNo: existing.data['billNo'] as String?);
  }

  /// Gives an order its sequential bill number if it doesn't have one yet
  /// (e.g. it was created offline). Safe to call repeatedly.
  Future<void> ensureBillNumber(String id) async {
    final now = DateTime.now();
    final ref = _orders.doc(id);
    final seed = await _billSeed(now);
    await FirebaseFirestore.instance.runTransaction<void>((tx) async {
      final billRef = FirestorePaths.cafeCounter(billCounterName(now));
      final reads = await Future.wait([tx.get(ref), tx.get(billRef)]);
      final order = reads[0];
      final has = order.data()?['billNo'];
      if (!order.exists || (has is String && has.isNotEmpty)) return;
      final seq = _takeBillSeq(tx, billRef, reads[1], seed);
      tx.update(ref, _billFields(now, seq));
    });
  }

  Map<String, dynamic> _billFields(DateTime now, int seq) => {
        'billSeq': seq,
        'billNo': formatBillNumber(now, seq),
        'billFy': financialYear(now),
        'billKey': billKey(now, seq),
      };

  /// Which counters already exist (so the bill-number queries run only once
  /// per financial year, not on every order).
  final Set<String> _knownCounters = {};

  /// First number of the year's series when its counter doesn't exist yet:
  /// right after the latest existing bill (null = counter exists, no query).
  Future<int?> _billSeed(DateTime now) async {
    final name = billCounterName(now);
    if (_knownCounters.contains(name)) return null;
    final c = await FirestorePaths.cafeCounter(name).get();
    if (c.exists && c.data()?['next'] != null) {
      _knownCounters.add(name);
      return null;
    }
    return await _lastSeqInOrders(now) + 1;
  }

  /// Highest bill number this financial year among bills that still exist.
  Future<int> _lastSeqInOrders(DateTime now) async {
    var last = 0;
    final byKey = await _orders.orderBy('billKey', descending: true).limit(1).get();
    if (byKey.docs.isNotEmpty) {
      last = seqInYear((byKey.docs.first.data()['billKey'] as num?)?.toInt(), now) ?? 0;
    }
    // Bills numbered before billKey existed only have billSeq/billFy.
    final bySeq = await _orders.orderBy('billSeq', descending: true).limit(1).get();
    if (bySeq.docs.isNotEmpty) {
      final d = bySeq.docs.first.data();
      final seq = (d['billSeq'] as num?)?.toInt() ?? 0;
      if (d['billFy'] == financialYear(now) && seq > last) last = seq;
    }
    return last;
  }

  /// Takes the next number from the counter snapshot read in [tx] (write
  /// only; the caller has done all reads). [seed] is used when the counter
  /// doesn't exist yet.
  int _takeBillSeq(Transaction tx, DocumentReference<Map<String, dynamic>> billRef,
      DocumentSnapshot<Map<String, dynamic>> counter, int? seed) {
    final seq = (counter.data()?['next'] as num?)?.toInt() ?? seed ?? 1;
    tx.set(billRef, {'next': seq + 1, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return seq;
  }

  /// Never let numbering problems block taking payment.
  Future<void> _tryEnsureBillNumber(String id) async {
    try {
      await ensureBillNumber(id);
    } catch (e) {
      debugPrint('Bill number not assigned for $id: $e');
    }
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
    bool assignBillNumber = true,
  }) async {
    if (assignBillNumber && order.data['billNo'] == null) await _tryEnsureBillNumber(order.id);
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
  Future<Map<String, dynamic>> complete(String id, {bool assignBillNumber = true}) async {
    if (assignBillNumber) await _tryEnsureBillNumber(id);
    await _orders.doc(id).update({
      'status': 'completed',
      'kitchenStatus': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    final fresh = await _orders.doc(id).get();
    return fresh.data() ?? {};
  }

  /// Deletes an order. If it was the latest bill of this year's series, the
  /// series goes back so the next bill follows the latest one that remains.
  Future<void> delete(String id) async {
    final ref = _orders.doc(id);
    final snap = await ref.get();
    await ref.delete();
    final d = snap.data();
    final seq = (d?['billSeq'] as num?)?.toInt();
    final now = DateTime.now();
    if (seq == null || d?['billFy'] != financialYear(now)) return;
    try {
      final last = await _lastSeqInOrders(now);
      final billRef = FirestorePaths.cafeCounter(billCounterNameForFy(financialYear(now)));
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final c = await tx.get(billRef);
        final next = (c.data()?['next'] as num?)?.toInt();
        if (next == null) return;
        final rewound = rewindAfterDelete(counterNext: next, deletedSeq: seq, lastSeqInOrders: last);
        if (rewound != null) tx.update(billRef, {'next': rewound, 'updatedAt': FieldValue.serverTimestamp()});
      });
    } catch (e) {
      debugPrint('Bill series not rewound after delete: $e');
    }
  }

  /// Adds an off-menu item (with the manager's price) to an existing order.
  Future<void> addCustomItem(PosOrder order, Map<String, dynamic> line) async {
    final items = [for (final e in order.items) {...e}];
    final i = items.indexWhere((l) => l['custom'] == true && l['name'] == line['name'] && l['price'] == line['price']);
    if (i != -1) {
      items[i]['qty'] = ((items[i]['qty'] ?? 1) as num).toInt() + ((line['qty'] ?? 1) as num).toInt();
    } else {
      items.add({...line});
    }
    await _orders.doc(order.id).update(_recalc(order, items));
  }

  /// New items + totals for [order], keeping its GST setting and discount.
  Map<String, dynamic> _recalc(PosOrder order, List<Map<String, dynamic>> items) {
    final type = Bill.parseType(order.data['discountType']);
    final value = ((order.data['discountValue'] ?? 0) as num).toDouble();
    final bill = Bill.compute(
      items: items,
      gstEnabled: order.hasGst,
      gstPercent: ((order.data['gstPercentage'] ?? 5) as num).toDouble(),
      discountType: type,
      discountValue: value,
    );
    return {
      'items': items,
      'subtotal': bill.subtotal,
      'totalPrice': bill.total,
      if (type != DiscountType.none) 'discountGiven': bill.discount,
    };
  }

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

/// Order status after an edit: new items go (back) to the kitchen, otherwise
/// (e.g. an item removed or an extra off-menu item added) it stays as it was.
String statusAfterEdit(String current, {required bool hasNewItems}) {
  if (hasNewItems) return 'pending';
  return const ['pending', 'preparing', 'ready'].contains(current) ? current : 'pending';
}
