import 'dart:async';

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
  OrderService._() {
    FirestorePaths.onCafeChanged.add(resetStreams);
  }
  static final instance = OrderService._();

  CollectionReference<Map<String, dynamic>> get _orders => FirestorePaths.orders();

  /// Orders the daily screens need (Dashboard, Tables, Takeaway, Kitchen,
  /// alerts, nav badges): every unfinished order + everything created since
  /// the 1st of last month. One shared listener for the whole session, so
  /// switching screens is instant and old history is never re-downloaded.
  Stream<List<PosOrder>> watchLive() => _shared('live', () {
        final now = DateTime.now();
        final since = Timestamp.fromDate(DateTime(now.year, now.month - 1));
        return mergeOrderSnapshots([
          _orders.where('status', whereIn: kActiveStatuses).snapshots(),
          _orders.where('createdAt', isGreaterThanOrEqualTo: since).snapshots(),
        ]);
      });

  /// Orders created in [from, to) (the Orders screen's date filter).
  Stream<List<PosOrder>> watchRange(DateTime from, DateTime to) => _orders
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('createdAt', isLessThan: Timestamp.fromDate(to))
      .snapshots()
      .map((s) => s.docs.map(PosOrder.fromDoc).toList());

  /// Every order ever (Reports, Customers only).
  Stream<List<PosOrder>> watchHistory() =>
      _shared('history', () => _orders.snapshots().map((s) => s.docs.map(PosOrder.fromDoc).toList()));

  final Map<String, SharedLatest<List<PosOrder>>> _streams = {};
  String? _streamsCafe;

  Stream<List<PosOrder>> _shared(String key, Stream<List<PosOrder>> Function() open) {
    final cafe = FirestorePaths.activeCafeId;
    if (cafe != _streamsCafe) resetStreams();
    _streamsCafe = cafe;
    return _streams.putIfAbsent(key, () => SharedLatest(open)).stream;
  }

  /// Closes the shared listeners (sign-out / other cafe).
  void resetStreams() {
    for (final s in _streams.values) {
      s.close();
    }
    _streams.clear();
    _streamsCafe = null;
  }

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
        // One transaction: next bill number in the cafe's series and the next
        // daily takeaway token (so two devices never share a number). Both
        // counters are read together: one read round trip, then the commit.
        final r = await _txWithBillSeed<({int? token, String? billNo})>((tx, seed) async {
          final billRef = FirestorePaths.cafeCounter(billCounterName(now));
          final tokenRef = FirestorePaths.cafeCounter('takeaway_${takeawayDayKey(now)}');
          // All reads must come before writes in a transaction.
          final reads = await Future.wait([
            if (assignBillNumber) tx.get(billRef),
            if (wantToken) tx.get(tokenRef),
          ]);
          final extra = <String, dynamic>{};
          String? billNo;
          if (assignBillNumber) {
            final seq = _takeBillSeq(tx, billRef, reads.first, seed);
            if (seq == null) return null; // series not started: seed it first
            billNo = formatBillNumber(now, seq);
            extra.addAll(_billFields(now, seq));
          }
          int? token;
          if (wantToken) {
            token = (reads.last.data()?['next'] as num?)?.toInt() ?? 1;
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
        unawaited(ref.set(data).catchError((Object e) => debugPrint('Order not saved: $e')));
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
    await _txWithBillSeed<bool>((tx, seed) async {
      final billRef = FirestorePaths.cafeCounter(billCounterName(now));
      final reads = await Future.wait([tx.get(ref), tx.get(billRef)]);
      if (!reads[0].exists || hasBillNumber(reads[0].data()!)) return true;
      final seq = _takeBillSeq(tx, billRef, reads[1], seed);
      if (seq == null) return null;
      tx.update(ref, _billFields(now, seq));
      return true;
    });
  }

  Map<String, dynamic> _billFields(DateTime now, int seq) => {
        'billSeq': seq,
        'billNo': formatBillNumber(now, seq),
        'billFy': financialYear(now),
        'billKey': billKey(now, seq),
      };

  /// Runs [body] in a transaction. [body] returns null when this year's bill
  /// series has no counter yet; then the series is started right after the
  /// latest existing bill and [body] runs again. (Only happens once a year,
  /// so normal orders never pay for the search.)
  Future<T> _txWithBillSeed<T extends Object>(Future<T?> Function(Transaction tx, int? seed) body) async {
    final first = await FirestorePaths.db.runTransaction<T?>((tx) => body(tx, null));
    if (first != null) return first;
    final seed = await _lastSeqInOrders(DateTime.now()) + 1;
    final second = await FirestorePaths.db.runTransaction<T?>((tx) => body(tx, seed));
    if (second == null) throw StateError('Bill series could not be started');
    return second;
  }

  /// Takes the next number from the counter [counter] read in [tx], or null
  /// when the counter doesn't exist and no [seed] is given (nothing written).
  int? _takeBillSeq(Transaction tx, DocumentReference<Map<String, dynamic>> billRef,
      DocumentSnapshot<Map<String, dynamic>> counter, int? seed) {
    final seq = (counter.data()?['next'] as num?)?.toInt() ?? seed;
    if (seq == null) return null;
    tx.set(billRef, {'next': seq + 1, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return seq;
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

  Future<void> setStatus(String id, String status) =>
      _orders.doc(id).update({'status': status, 'kitchenStatus': status});

  /// Records payment (and optionally completes the order / frees the table).
  /// Applies the discount and recomputes the total with [Bill.compute].
  /// Returns the order as saved (for the receipt) without reading it again.
  Future<Map<String, dynamic>> settle({
    required PosOrder order,
    required PaymentMethod method,
    required DiscountType discountType,
    required double discountValue,
    required double? cashReceived,
    required bool complete,
    bool assignBillNumber = true,
  }) {
    return _patchOrder(order, assignBillNumber: assignBillNumber, (cur) {
      final bill = Bill.compute(
        items: ((cur['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        gstEnabled: cur['hasGst'] == true,
        gstPercent: ((cur['gstPercentage'] ?? 5) as num).toDouble(),
        discountType: discountType,
        discountValue: discountValue,
      );
      final cash = method == PaymentMethod.cash && cashReceived != null;
      return OrderPatch(
        {
          'subtotal': bill.subtotal,
          'totalPrice': bill.total,
          'paymentStatus': method.status,
          'paymentMethod': method.name,
          if (discountType != DiscountType.none) 'discountType': discountType.name,
          if (discountType != DiscountType.none) 'discountValue': discountValue,
          if (bill.discount > 0) 'discountGiven': bill.discount,
          if (cash) 'cashReceived': cashReceived,
          if (cash) 'changeReturned': (cashReceived - bill.total).clamp(0, double.infinity),
          if (complete) 'status': 'completed',
          if (complete) 'kitchenStatus': 'completed',
        },
        remove: {
          if (discountType == DiscountType.none) ...['discountType', 'discountValue'],
          if (bill.discount <= 0) 'discountGiven',
          if (!cash) ...['cashReceived', 'changeReturned'],
        },
        serverTime: {'paidAt', if (complete) 'completedAt'},
      );
    });
  }

  /// Frees the table without changing payment (original "Done" action).
  Future<Map<String, dynamic>> complete(PosOrder order, {bool assignBillNumber = true}) => _patchOrder(
        order,
        assignBillNumber: assignBillNumber,
        (_) => OrderPatch({'status': 'completed', 'kitchenStatus': 'completed'}, serverTime: {'completedAt'}),
      );

  /// Applies [build]'s changes to [order]. Usually one plain update (the bill
  /// number was given when the order was placed); only an order without a
  /// number needs a transaction to take the next one. If the transaction
  /// can't run (offline), the change is still saved and payment is never
  /// blocked. Returns the order as it is now, without reading it back.
  Future<Map<String, dynamic>> _patchOrder(
    PosOrder order,
    OrderPatch Function(Map<String, dynamic> current) build, {
    required bool assignBillNumber,
  }) async {
    final ref = _orders.doc(order.id);
    if (assignBillNumber && !hasBillNumber(order.data)) {
      final now = DateTime.now();
      try {
        return await _txWithBillSeed<Map<String, dynamic>>((tx, seed) async {
          final billRef = FirestorePaths.cafeCounter(billCounterName(now));
          final reads = await Future.wait([tx.get(ref), tx.get(billRef)]);
          final cur = reads[0].data() ?? order.data;
          final patch = build(cur);
          final extra = <String, dynamic>{};
          if (!hasBillNumber(cur)) {
            final seq = _takeBillSeq(tx, billRef, reads[1], seed);
            if (seq == null) return null;
            extra.addAll(_billFields(now, seq));
          }
          tx.update(ref, {...patch.toWrite(), ...extra});
          return {...patch.applyTo(cur), ...extra};
        }).timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint('Bill number not assigned for ${order.id}: $e');
      }
    }
    final patch = build(order.data);
    // Not awaited past a short wait: offline, Firestore keeps the change and
    // sends it later; the screen already shows it.
    try {
      await ref.update(patch.toWrite()).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('Order ${order.id} saved offline; will sync later');
    }
    return patch.applyTo(order.data);
  }

  /// Deletes an order. If it was the latest bill of this year's series, the
  /// series goes back (in the background) so the next bill follows the
  /// latest one that remains.
  Future<void> delete(String id, {Map<String, dynamic>? data}) async {
    final ref = _orders.doc(id);
    final d = data ?? (await ref.get()).data();
    await ref.delete();
    final seq = (d?['billSeq'] as num?)?.toInt();
    final now = DateTime.now();
    if (seq == null || d?['billFy'] != financialYear(now)) return;
    unawaited(() async {
      try {
        final last = await _lastSeqInOrders(now);
        final billRef = FirestorePaths.cafeCounter(billCounterNameForFy(financialYear(now)));
        await FirestorePaths.db.runTransaction<void>((tx) async {
          final c = await tx.get(billRef);
          final next = (c.data()?['next'] as num?)?.toInt();
          if (next == null) return;
          final rewound = rewindAfterDelete(counterNext: next, deletedSeq: seq, lastSeqInOrders: last);
          if (rewound != null) tx.update(billRef, {'next': rewound, 'updatedAt': FieldValue.serverTimestamp()});
        });
      } catch (e) {
        debugPrint('Bill series not rewound after delete: $e');
      }
    }());
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

/// Statuses of orders that are still running (table busy / in the kitchen).
const kActiveStatuses = ['pending', 'preparing', 'ready'];

bool hasBillNumber(Map<String, dynamic> order) {
  final b = order['billNo'];
  return b is String && b.isNotEmpty;
}

/// A change to an order: fields to set, fields to remove and fields that get
/// the server time. [toWrite] is what goes to Firestore; [applyTo] is the
/// same change applied locally (for the receipt), with the device time.
class OrderPatch {
  OrderPatch(this.set, {this.remove = const {}, this.serverTime = const {}});
  final Map<String, dynamic> set;
  final Set<String> remove;
  final Set<String> serverTime;

  Map<String, dynamic> toWrite() => {
        ...set,
        for (final k in remove) k: FieldValue.delete(),
        for (final k in serverTime) k: FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> applyTo(Map<String, dynamic> current) {
    final now = Timestamp.now();
    return {
      for (final e in current.entries)
        if (!remove.contains(e.key)) e.key: e.value,
      ...set,
      for (final k in serverTime) k: now,
    };
  }
}

/// Merges several order snapshot streams (e.g. "running" + "recent") into
/// one list without duplicates. Emits once every source has delivered.
Stream<List<PosOrder>> mergeOrderSnapshots(List<Stream<QuerySnapshot<Map<String, dynamic>>>> sources) {
  late final StreamController<List<PosOrder>> out;
  final latest = List<Map<String, PosOrder>?>.filled(sources.length, null);
  final subs = <StreamSubscription>[];
  void emit() {
    if (latest.any((m) => m == null)) return;
    final merged = <String, PosOrder>{};
    for (final m in latest) {
      merged.addAll(m!);
    }
    out.add(merged.values.toList());
  }

  out = StreamController<List<PosOrder>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        subs.add(sources[i].listen((snap) {
          latest[i] = {for (final d in snap.docs) d.id: PosOrder.fromDoc(d)};
          emit();
        }, onError: out.addError));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return out.stream;
}

/// One upstream subscription shared by many listeners; a new listener gets
/// the latest value immediately. The upstream stays open until [close].
class SharedLatest<T> {
  SharedLatest(this._open);
  final Stream<T> Function() _open;
  StreamSubscription<T>? _sub;
  T? _last;
  Object? _error;
  final Set<MultiStreamController<T>> _listeners = {};

  Stream<T> get stream => Stream<T>.multi((c) {
        _listeners.add(c);
        if (_last != null) {
          c.add(_last as T);
        } else if (_error != null) {
          c.addError(_error!);
        }
        c.onCancel = () => _listeners.remove(c);
        _sub ??= _open().listen(
          (v) {
            _last = v;
            _error = null;
            for (final l in [..._listeners]) {
              l.add(v);
            }
          },
          onError: (Object e) {
            _error = e;
            for (final l in [..._listeners]) {
              l.addError(e);
            }
          },
        );
      });

  void close() {
    _sub?.cancel();
    _sub = null;
    _last = null;
    _error = null;
  }
}
