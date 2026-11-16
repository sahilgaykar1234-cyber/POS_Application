import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/data/firestore_paths.dart';
import '../../core/services/audit_service.dart';
import '../orders/order_model.dart';

/// Customer personal data (name + mobile) on bills – DPDP-friendly tools.
/// Removing data keeps the bill itself (amounts, items, bill number); only
/// the customer's name and number are cleared.
class CustomerPrivacy {
  CustomerPrivacy._();
  static final instance = CustomerPrivacy._();

  CollectionReference<Map<String, dynamic>> get _orders => FirestorePaths.orders();

  /// What a bill's customer fields become after removal (pure, unit-tested).
  static Map<String, dynamic> anonymizedFields(Map<String, dynamic> order) {
    final table = (order['tableNo'] ?? '').toString().trim();
    return {
      'customerPhone': '',
      'customerName': table.isEmpty ? 'Guest' : 'Guest (Table $table)',
      'customerRemovedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Removes one customer's name and number from all their bills
  /// ("delete my data" request). Returns how many bills were changed.
  Future<int> removeCustomer({required String phone, required String name}) async {
    final q = phone.isNotEmpty
        ? await _orders.where('customerPhone', isEqualTo: phone).get()
        : await _orders.where('customerName', isEqualTo: name).get();
    final n = await _anonymize(q.docs);
    await AuditService.instance.log('customer.delete', details: {
      'phone': maskPhone(phone),
      'bills': n,
    });
    return n;
  }

  /// Clears customer names and numbers on bills older than [months].
  Future<int> removeOlderThan(int months, {DateTime? now}) async {
    final n0 = now ?? DateTime.now();
    final cutoff = DateTime(n0.year, n0.month - months, n0.day);
    final q = await _orders.where('createdAt', isLessThan: Timestamp.fromDate(cutoff)).get();
    final withData = q.docs.where((d) {
      final o = PosOrder.fromDoc(d);
      return o.customerPhone.isNotEmpty || (o.data['customerRemovedAt'] == null && o.takeawayName.isNotEmpty && o.takeawayName != 'Walk-in');
    }).toList();
    final n = await _anonymize(withData);
    await AuditService.instance.log('customer.retention', details: {'olderThanMonths': months, 'bills': n});
    return n;
  }

  Future<int> _anonymize(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    var count = 0;
    for (var i = 0; i < docs.length; i += 400) {
      final batch = FirestorePaths.db.batch();
      for (final d in docs.skip(i).take(400)) {
        batch.update(d.reference, anonymizedFields(d.data()));
        count++;
      }
      await batch.commit();
    }
    return count;
  }
}
