import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/utils/formatters.dart';

/// A cafe as seen by the Master Admin.
class CafeSummary {
  CafeSummary(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;

  String get name => (data['name'] ?? 'Unnamed cafe').toString();
  String get status => (data['status'] ?? CafeStatus.active).toString();
  String get ownerName => (data['ownerName'] ?? '').toString();
  String get ownerEmail => (data['ownerEmail'] ?? '').toString();
  String get contactNumber => (data['contactNumber'] ?? '').toString();
  String get address => (data['address'] ?? '').toString();
  String get gstNumber => (data['gstNumber'] ?? '').toString();
  bool get legacyData => data['legacyData'] == true;
  DateTime? get createdAt => Fmt.toDate(data['createdAt']);

  Map<String, dynamic> get subscription =>
      data['subscription'] is Map ? Map<String, dynamic>.from(data['subscription']) : const {};
  String? get planName => subscription['planName']?.toString();
  String get subscriptionStatus => (subscription['status'] ?? '—').toString();
  DateTime? get expiryDate => Fmt.toDate(subscription['expiryDate']);
  DateTime? get startDate => Fmt.toDate(subscription['startDate']);
  double get amount => (subscription['amount'] is num) ? (subscription['amount'] as num).toDouble() : 0;
  String get paymentStatus => (subscription['paymentStatus'] ?? '—').toString();

  bool get isDeleted => status == CafeStatus.deleted;

  /// Payment due and the subscription period has not ended yet.
  bool isPaymentPending(DateTime now) =>
      !isDeleted && paymentStatus == 'pending' && (expiryDate == null || expiryDate!.isAfter(now));

  /// Subscription period has ended (by date or status) without renewal.
  bool isOverdue(DateTime now) =>
      !isDeleted &&
      (subscriptionStatus == SubscriptionStatus.expired || (expiryDate != null && !expiryDate!.isAfter(now)));

  CafeAccess access(DateTime now) => evaluateCafeAccess(data, now);
}

class SubscriptionPlan {
  SubscriptionPlan(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get name => (data['name'] ?? '').toString();

  /// monthly | yearly | custom
  String get billingCycle => (data['billingCycle'] ?? 'monthly').toString();
  double get price => (data['price'] is num) ? (data['price'] as num).toDouble() : 0;
  int get durationDays => (data['durationDays'] is num) ? (data['durationDays'] as num).toInt() : 30;
  String get description => (data['description'] ?? '').toString();
  bool get isActive => data['isActive'] != false;

  String get cycleLabel => switch (billingCycle) {
        'monthly' => 'Monthly',
        'yearly' => 'Yearly',
        _ => '$durationDays days',
      };
}

class SubscriptionPayment {
  SubscriptionPayment(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get cafeId => (data['cafeId'] ?? '').toString();
  String get cafeName => (data['cafeName'] ?? '').toString();
  String get receiptNo => (data['receiptNo'] ?? '').toString();
  double get amount => (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0;
  String get method => (data['method'] ?? '').toString();
  String get referenceId => (data['referenceId'] ?? '').toString();
  String get notes => (data['notes'] ?? '').toString();
  String get planName => (data['planName'] ?? '').toString();
  DateTime? get paidAt => Fmt.toDate(data['paidAt']);
  DateTime? get periodStart => Fmt.toDate(data['periodStart']);
  DateTime? get periodEnd => Fmt.toDate(data['periodEnd']);
}

class CreateCafeResult {
  CreateCafeResult(this.cafeId, this.receiptNo, this.managerEmail, this.managerSetupLink, this.managerError);
  final String cafeId;
  final String? receiptNo;
  final String? managerEmail;
  final String? managerSetupLink;
  final String? managerError;
}

const paymentMethods = ['Cash', 'UPI', 'Bank Transfer', 'Card', 'Cheque', 'Other'];

/// Everything the Master Admin panel reads and writes. Privileged multi-step
/// actions go through Cloud Functions; simple edits are direct writes that
/// firestore.rules only allow for the Super Admin.
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);
  String get _uid => AuthService.instance.currentUser?.uid ?? 'unknown';

  // ---------------------------------------------------------------- streams

  Stream<List<CafeSummary>> watchCafes() => FirestorePaths.cafes().snapshots().map((s) {
        final list = s.docs.map((d) => CafeSummary(d.id, d.data())).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  Stream<CafeSummary?> watchCafe(String id) =>
      FirestorePaths.cafe(id).snapshots().map((d) => d.exists ? CafeSummary(d.id, d.data()!) : null);

  /// {manager: n, captain: n} across all cafes (excluding disabled).
  Stream<Map<String, int>> watchStaffCounts() => FirestorePaths.users().snapshots().map((s) {
        final counts = {'manager': 0, 'captain': 0};
        for (final d in s.docs) {
          final r = d.data()['role'];
          if (d.data()['status'] == 'disabled') continue;
          if (counts.containsKey(r)) counts[r] = counts[r]! + 1;
        }
        return counts;
      });

  Stream<List<SubscriptionPlan>> watchPlans() => FirestorePaths.plans().snapshots().map((s) {
        final list = s.docs.map((d) => SubscriptionPlan(d.id, d.data())).toList();
        list.sort((a, b) => a.price.compareTo(b.price));
        return list;
      });

  /// All payments (newest first), or one cafe's.
  Stream<List<SubscriptionPayment>> watchPayments({String? cafeId}) {
    Query<Map<String, dynamic>> q = FirestorePaths.subscriptionPayments();
    if (cafeId != null) q = q.where('cafeId', isEqualTo: cafeId);
    return q.snapshots().map((s) {
      final list = s.docs.map((d) => SubscriptionPayment(d.id, d.data())).toList();
      list.sort((a, b) => (b.paidAt ?? DateTime(0)).compareTo(a.paidAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<Map<String, dynamic>>> watchAdminNotifications({int limit = 30}) => FirestorePaths.notifications()
      .where('audience', isEqualTo: 'superAdmin')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Future<void> markNotificationRead(String id) =>
      FirestorePaths.notifications().doc(id).update({'read': true, 'readAt': FieldValue.serverTimestamp()});

  Stream<List<Map<String, dynamic>>> watchAuditLogs({String? cafeId, int limit = 100}) {
    Query<Map<String, dynamic>> q = FirestorePaths.auditLogs();
    if (cafeId != null) q = q.where('cafeId', isEqualTo: cafeId);
    return q.orderBy('at', descending: true).limit(limit).snapshots().map((s) => s.docs.map((d) => d.data()).toList());
  }

  // ---------------------------------------------------------------- cafes

  Future<CreateCafeResult> createCafe(Map<String, dynamic> input) async {
    final res = await _fn.httpsCallable('createCafe').call<Map<String, dynamic>>(input);
    final d = res.data;
    return CreateCafeResult(
      d['cafeId'].toString(),
      d['receiptNo']?.toString(),
      d['managerEmail']?.toString(),
      d['managerSetupLink']?.toString(),
      d['managerError']?.toString(),
    );
  }

  /// Also emails the invite link to the first manager (best effort).
  Future<void> sendInviteEmail(String email) async {
    try {
      await AuthService.instance.sendPasswordResetEmail(email);
    } catch (_) {}
  }

  Future<void> updateCafeProfile(String cafeId, Map<String, dynamic> fields) async {
    await FirestorePaths.cafe(cafeId).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
    await audit('cafe.update', cafeId: cafeId, details: {'fields': fields.keys.toList()});
  }

  Future<void> setCafeStatus(CafeSummary cafe, String status) async {
    final update = <String, dynamic>{'status': status, 'updatedAt': FieldValue.serverTimestamp()};
    if (cafe.isDeleted && status != CafeStatus.deleted) update['deletedAt'] = FieldValue.delete();
    await FirestorePaths.cafe(cafe.id).update(update);
    await audit('cafe.status', cafeId: cafe.id, details: {'from': cafe.status, 'to': status});
  }

  Future<int> deleteCafe(String cafeId, String confirmName) async {
    final res = await _fn.httpsCallable('deleteCafe').call<Map<String, dynamic>>({
      'cafeId': cafeId,
      'confirmName': confirmName,
    });
    return (res.data['staffDisabled'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------- plans

  Future<void> savePlan({
    String? id,
    required String name,
    required String billingCycle,
    required double price,
    required int durationDays,
    String description = '',
    bool isActive = true,
  }) async {
    final data = {
      'name': name.trim(),
      'billingCycle': billingCycle,
      'price': price,
      'durationDays': durationDays,
      'description': description.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      final ref = await FirestorePaths.plans().add({...data, 'createdAt': FieldValue.serverTimestamp()});
      await audit('plan.create', details: {'planId': ref.id, 'name': name, 'price': price});
    } else {
      await FirestorePaths.plans().doc(id).set(data, SetOptions(merge: true));
      await audit('plan.update', details: {'planId': id, 'name': name, 'price': price});
    }
  }

  // ---------------------------------------------------------------- subscription

  /// Assigns a plan/period to a cafe (no payment recorded).
  Future<void> setSubscription(
    CafeSummary cafe, {
    SubscriptionPlan? plan,
    required String status,
    required DateTime start,
    required DateTime expiry,
    required double amount,
    required String paymentStatus,
  }) async {
    await FirestorePaths.cafe(cafe.id).update({
      'subscription.planId': plan?.id,
      'subscription.planName': plan?.name,
      'subscription.billingCycle': plan?.billingCycle,
      'subscription.status': status,
      'subscription.startDate': Timestamp.fromDate(start),
      'subscription.expiryDate': Timestamp.fromDate(expiry),
      'subscription.amount': amount,
      'subscription.paymentStatus': paymentStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await audit('subscription.set', cafeId: cafe.id, details: {
      'plan': plan?.name,
      'status': status,
      'expiry': Fmt.date(expiry),
      'amount': amount,
    });
  }

  /// Records a payment with a sequential receipt number. If [extendTo] is
  /// given, the subscription is renewed (active, paid) until that date.
  Future<String> recordPayment({
    required CafeSummary cafe,
    required double amount,
    required String method,
    String referenceId = '',
    String notes = '',
    required DateTime paidAt,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? planName,
    bool markPaid = true,
    DateTime? extendTo,
  }) async {
    final db = FirebaseFirestore.instance;
    final counterRef = FirestorePaths.counter('subscriptionReceipts');
    final paymentRef = FirestorePaths.subscriptionPayments().doc();
    late String receiptNo;

    await db.runTransaction((tx) async {
      final counter = await tx.get(counterRef);
      final next = (counter.data()?['next'] as num?)?.toInt() ?? 1;
      receiptNo = 'RCPT-${next.toString().padLeft(4, '0')}';
      tx.set(counterRef, {'next': next + 1}, SetOptions(merge: true));

      tx.set(paymentRef, {
        'cafeId': cafe.id,
        'cafeName': cafe.name,
        'receiptNo': receiptNo,
        'amount': amount,
        'method': method,
        'referenceId': referenceId.trim(),
        'notes': notes.trim(),
        'planName': planName ?? cafe.planName,
        'periodStart': periodStart == null ? null : Timestamp.fromDate(periodStart),
        'periodEnd': periodEnd == null ? null : Timestamp.fromDate(periodEnd),
        'paidAt': Timestamp.fromDate(paidAt),
        'recordedBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final cafeUpdate = <String, dynamic>{
        'subscription.lastPaymentAt': Timestamp.fromDate(paidAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (markPaid) cafeUpdate['subscription.paymentStatus'] = 'paid';
      if (extendTo != null) {
        cafeUpdate['subscription.expiryDate'] = Timestamp.fromDate(extendTo);
        cafeUpdate['subscription.status'] = SubscriptionStatus.active;
        if (periodStart != null) cafeUpdate['subscription.startDate'] = Timestamp.fromDate(periodStart);
      }
      tx.update(FirestorePaths.cafe(cafe.id), cafeUpdate);
    });

    await audit('payment.record', cafeId: cafe.id, details: {
      'receiptNo': receiptNo,
      'amount': amount,
      'method': method,
      if (extendTo != null) 'extendedTo': Fmt.date(extendTo),
    });
    return receiptNo;
  }

  // ---------------------------------------------------------------- audit

  Future<void> audit(String action, {String? cafeId, Map<String, dynamic>? details}) async {
    try {
      await FirestorePaths.auditLogs().add({
        'action': action,
        'actorUid': _uid,
        'actorRole': 'superAdmin',
        'cafeId': cafeId,
        'details': details ?? const {},
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Audit failure must never block the admin action itself.
    }
  }
}
