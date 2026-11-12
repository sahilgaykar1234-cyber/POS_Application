import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/utils/business_day.dart';
import '../../core/utils/formatters.dart';
import 'admin_models.dart';

export 'admin_models.dart';

/// Operational numbers of one cafe (read with aggregate queries: counts and
/// sums only, the Super Admin never downloads a cafe's orders).
class CafeOpsSummary {
  const CafeOpsSummary({
    required this.categories,
    required this.menuItems,
    required this.availableItems,
    required this.ordersToday,
    required this.orders30d,
    required this.billed30d,
    required this.lastOrderAt,
  });

  /// null = that number could not be read (e.g. offline); shown as "—".
  final int? categories, menuItems, availableItems, ordersToday, orders30d;
  final double? billed30d;
  final DateTime? lastOrderAt;
}

/// Everything the Super Admin panel reads and writes. Only the Super Admin
/// can do these writes (enforced by firestore.rules, not just the UI).
/// Logins (Firebase Auth users and their role claims) are created / turned
/// off only with the local admin script: that needs the Admin SDK, which
/// must never run in the app.
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  FirebaseFirestore get _db => FirestorePaths.db;
  String get _uid => AuthService.instance.currentUser?.uid ?? 'unknown';

  // ---------------------------------------------------------------- streams

  Stream<List<CafeSummary>> watchCafes() => FirestorePaths.cafes().snapshots().map((s) {
    final list = s.docs.map((d) => CafeSummary(d.id, d.data())).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });

  Stream<CafeSummary?> watchCafe(String id) => FirestorePaths.cafe(id).snapshots().map((d) => d.exists ? CafeSummary(d.id, d.data()!) : null);

  /// Every login with a role (users/{uid}, written by the admin script).
  Stream<List<StaffMember>> watchStaff() => FirestorePaths.users().snapshots().map((s) {
    final list = s.docs.map((d) => StaffMember(d.id, d.data())).toList();
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  });

  Stream<List<SubscriptionPlan>> watchPlans() => FirestorePaths.plans().snapshots().map((s) {
    final list = s.docs.map((d) => SubscriptionPlan(d.id, d.data())).toList();
    list.sort((a, b) => a.tier.index != b.tier.index ? a.tier.index.compareTo(b.tier.index) : a.monthlyPrice.compareTo(b.monthlyPrice));
    return list;
  });

  /// All subscription payments (newest first), or one cafe's.
  Stream<List<SubscriptionPayment>> watchPayments({String? cafeId}) {
    Query<Map<String, dynamic>> q = FirestorePaths.subscriptionPayments();
    if (cafeId != null) q = q.where('cafeId', isEqualTo: cafeId);
    return q.snapshots().map((s) {
      final list = s.docs.map((d) => SubscriptionPayment(d.id, d.data())).toList();
      list.sort((a, b) => (b.paidAt ?? DateTime(0)).compareTo(a.paidAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<Map<String, dynamic>>> watchAuditLogs({String? cafeId, int limit = 200}) {
    Query<Map<String, dynamic>> q = FirestorePaths.auditLogs();
    if (cafeId != null) q = q.where('cafeId', isEqualTo: cafeId);
    return q.snapshots().map((s) {
      final list = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      list.sort((a, b) => (Fmt.toDate(b['at']) ?? DateTime(0)).compareTo(Fmt.toDate(a['at']) ?? DateTime(0)));
      return list.take(limit).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> watchSubscriptionHistory(String cafeId) => FirestorePaths.subscriptionHistory(cafeId).snapshots().map((s) {
    final list = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    list.sort((a, b) => (Fmt.toDate(b['at']) ?? DateTime(0)).compareTo(Fmt.toDate(a['at']) ?? DateTime(0)));
    return list;
  });

  Stream<PlatformSettings> watchPlatformSettings() => FirestorePaths.platformSettings().snapshots().map((d) => PlatformSettings(d.data() ?? const {}));

  Stream<Map<String, dynamic>> watchCafeSettings(String cafeId) => FirestorePaths.businessSettings(cafeId).snapshots().map((d) => d.data() ?? const {});

  /// Menu + order counts for one cafe (aggregates only; the current
  /// business day uses the cafe's own day-end time). Each number is read on
  /// its own, so one failing query never hides the others.
  Future<CafeOpsSummary> cafeOps(String cafeId, {int dayEndsAt = BusinessDay.defaultCutoffMinutes}) async {
    final cafe = FirestorePaths.cafe(cafeId);
    final now = DateTime.now();
    final shifted = now.subtract(Duration(minutes: dayEndsAt));
    final todayStart = DateTime(shifted.year, shifted.month, shifted.day, 0, dayEndsAt);
    final since = Timestamp.fromDate(now.subtract(const Duration(days: 30)));
    final orders = cafe.collection('orders');
    final recent = orders.where('createdAt', isGreaterThanOrEqualTo: since);

    Future<Object?> safe(Future<Object?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        debugPrint('cafeOps($cafeId): $e');
        return null;
      }
    }

    final r = await Future.wait<Object?>([
      safe(() async => (await cafe.collection('categories').count().get()).count),
      safe(() async => (await cafe.collection('menuItems').count().get()).count),
      safe(() async => (await cafe.collection('menuItems').where('isAvailable', isEqualTo: false).count().get()).count),
      safe(() async => (await orders.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)).count().get()).count),
      safe(() async => (await recent.count().get()).count),
      // Needs the (createdAt, totalPrice) index from firestore.indexes.json.
      safe(() async => (await recent.aggregate(sum('totalPrice')).get()).getSum('totalPrice')),
      safe(() async {
        final last = await orders.orderBy('createdAt', descending: true).limit(1).get();
        return last.docs.isEmpty ? null : Fmt.toDate(last.docs.first.data()['createdAt']);
      }),
    ]);
    final items = r[1] as int?;
    final hidden = r[2] as int?;
    return CafeOpsSummary(
      categories: r[0] as int?,
      menuItems: items,
      availableItems: items == null || hidden == null ? null : items - hidden,
      ordersToday: r[3] as int?,
      orders30d: r[4] as int?,
      billed30d: r[5] as double?,
      lastOrderAt: r[6] as DateTime?,
    );
  }

  // ---------------------------------------------------------------- cafes

  /// Creates a cafe (record + its settings, optionally a trial). Its login
  /// is created afterwards in the panel (Add login).
  Future<String> createCafe({required Map<String, dynamic> profile, required int dayEndsAt, SubscriptionPlan? trialPlan, int? trialDays}) async {
    final ref = FirestorePaths.cafes().doc();
    final now = DateTime.now();
    final batch = _db.batch();
    final cafe = <String, dynamic>{...profile, 'status': CafeStatus.active, 'legacyData': false, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': _uid};
    if (trialDays != null && trialDays > 0) {
      cafe['subscription'] = {
        'planId': trialPlan?.id,
        'planName': trialPlan?.name ?? 'Free Trial',
        'billingCycle': 'trial',
        'status': SubscriptionStatus.trial,
        'startDate': Timestamp.fromDate(now),
        'expiryDate': Timestamp.fromDate(now.add(Duration(days: trialDays))),
        'amount': 0,
        'paymentStatus': 'none',
      };
    }
    batch.set(ref, cafe);
    batch.set(FirestorePaths.businessSettings(ref.id), {
      'shopName': profile['name'],
      'mobileNumber': profile['contactNumber'] ?? '',
      'address': profile['address'] ?? '',
      'gstNumber': profile['gstNumber'] ?? '',
      'email': profile['ownerEmail'] ?? '',
      'ownerName': profile['ownerName'] ?? '',
      'dayEndsAt': BusinessDay.format(dayEndsAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (trialDays != null && trialDays > 0) {
      batch.set(FirestorePaths.subscriptionHistory(ref.id).doc(), {
        'action': 'trial',
        'planName': trialPlan?.name ?? 'Free Trial',
        'status': SubscriptionStatus.trial,
        'expiryDate': Timestamp.fromDate(now.add(Duration(days: trialDays))),
        'amount': 0,
        'by': _uid,
        'at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await audit('cafe.create', cafeId: ref.id, details: {'name': profile['name'], 'trialDays': ?trialDays});
    return ref.id;
  }

  /// Updates the cafe record and its receipt settings (cafe-specific day end).
  Future<void> updateCafe(CafeSummary cafe, Map<String, dynamic> profile, {int? dayEndsAt}) async {
    final batch = _db.batch();
    batch.update(FirestorePaths.cafe(cafe.id), {...profile, 'updatedAt': FieldValue.serverTimestamp()});
    batch.set(FirestorePaths.businessSettings(cafe.id), {
      if (profile['name'] != null) 'shopName': profile['name'],
      if (profile['contactNumber'] != null) 'mobileNumber': profile['contactNumber'],
      if (profile['address'] != null) 'address': profile['address'],
      if (profile['gstNumber'] != null) 'gstNumber': profile['gstNumber'],
      'dayEndsAt': ?(dayEndsAt == null ? null : BusinessDay.format(dayEndsAt)),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await audit(
      'cafe.update',
      cafeId: cafe.id,
      details: {
        'fields': [...profile.keys, if (dayEndsAt != null) 'dayEndsAt'],
      },
    );
  }

  /// Active / inactive / suspended. Data is never touched.
  Future<void> setCafeStatus(CafeSummary cafe, String status) async {
    await FirestorePaths.cafe(cafe.id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
    await audit('cafe.status', cafeId: cafe.id, details: {'from': cafe.status, 'to': status});
  }

  // ---------------------------------------------------------------- plans

  Future<void> savePlan(String? id, Map<String, dynamic> fields) async {
    final data = {...fields, 'updatedAt': FieldValue.serverTimestamp()};
    if (id == null) {
      final ref = await FirestorePaths.plans().add({...data, 'createdAt': FieldValue.serverTimestamp()});
      await audit('plan.create', details: {'planId': ref.id, 'name': fields['name']});
    } else {
      await FirestorePaths.plans().doc(id).set(data, SetOptions(merge: true));
      await audit('plan.update', details: {'planId': id, 'name': fields['name']});
    }
  }

  /// Deletes a plan. Cafes on it keep their subscription (name, amount and
  /// dates are stored on the cafe); the plan just can't be assigned again.
  Future<void> deletePlan(SubscriptionPlan plan, {int usedBy = 0}) async {
    await FirestorePaths.plans().doc(plan.id).delete();
    await audit('plan.delete', details: {'planId': plan.id, 'name': plan.name, 'cafesOnPlan': usedBy});
  }

  /// Adds the recommended starter plans that don't exist yet (by name).
  Future<int> addRecommendedPlans(List<SubscriptionPlan> existing) async {
    final missing = missingRecommendedPlans(existing);
    if (missing.isEmpty) return 0;
    final batch = _db.batch();
    for (final p in missing) {
      batch.set(FirestorePaths.plans().doc(), {...p, 'isActive': true, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
    await audit(
      'plan.create',
      details: {
        'recommended': [for (final p in missing) p['name']],
      },
    );
    return missing.length;
  }

  // ---------------------------------------------------------- subscription

  /// Assigns (or changes) a cafe's plan and period. No payment is recorded
  /// here; payments are recorded separately when money is received.
  Future<void> assignPlan(
    CafeSummary cafe, {
    required SubscriptionPlan? plan,
    required String cycle, // monthly | yearly | trial | custom
    required String status,
    required DateTime start,
    required DateTime expiry,
    required double amount,
    required String paymentStatus, // paid | pending | none
  }) => _changeSubscription(
    cafe,
    'subscription.set',
    {
      'subscription.planId': plan?.id,
      'subscription.planName': plan?.name ?? 'Custom',
      'subscription.billingCycle': cycle,
      'subscription.status': status,
      'subscription.startDate': Timestamp.fromDate(start),
      'subscription.expiryDate': Timestamp.fromDate(expiry),
      'subscription.amount': amount,
      'subscription.paymentStatus': paymentStatus,
    },
    {
      'action': cafe.hasSubscription ? 'changed' : 'assigned',
      'planName': plan?.name ?? 'Custom',
      'status': status,
      'cycle': cycle,
      'startDate': Timestamp.fromDate(start),
      'expiryDate': Timestamp.fromDate(expiry),
      'amount': amount,
    },
  );

  /// Extends the current plan to [newExpiry] and makes it active.
  Future<void> renew(CafeSummary cafe, {required DateTime newExpiry, required String paymentStatus}) => _changeSubscription(
    cafe,
    'subscription.renew',
    {
      'subscription.status': paymentStatus == 'pending' ? SubscriptionStatus.pending : SubscriptionStatus.active,
      'subscription.expiryDate': Timestamp.fromDate(newExpiry),
      'subscription.paymentStatus': paymentStatus,
      if (cafe.expiryDate == null || !cafe.expiryDate!.isAfter(DateTime.now())) 'subscription.startDate': Timestamp.now(),
    },
    {
      'action': 'renewed',
      'planName': cafe.planName,
      'from': cafe.expiryDate == null ? null : Timestamp.fromDate(cafe.expiryDate!),
      'expiryDate': Timestamp.fromDate(newExpiry),
      'amount': cafe.amount,
    },
  );

  /// Stops renewal: the cafe keeps working until the current expiry date.
  Future<void> cancel(CafeSummary cafe) => _changeSubscription(
    cafe,
    'subscription.cancel',
    {'subscription.status': SubscriptionStatus.cancelled, 'subscription.cancelledAt': FieldValue.serverTimestamp()},
    {'action': 'cancelled', 'planName': cafe.planName, 'expiryDate': cafe.expiryDate == null ? null : Timestamp.fromDate(cafe.expiryDate!)},
  );

  Future<void> _changeSubscription(CafeSummary cafe, String auditAction, Map<String, dynamic> update, Map<String, dynamic> history) async {
    final batch = _db.batch();
    batch.update(FirestorePaths.cafe(cafe.id), {...update, 'updatedAt': FieldValue.serverTimestamp()});
    batch.set(FirestorePaths.subscriptionHistory(cafe.id).doc(), {...history, 'by': _uid, 'at': FieldValue.serverTimestamp()});
    await batch.commit();
    await audit(
      auditAction,
      cafeId: cafe.id,
      details: {
        for (final e in history.entries)
          if (e.value != null) e.key: e.value is Timestamp ? Fmt.date((e.value as Timestamp).toDate()) : e.value,
      },
    );
  }

  /// Records money received (manual: UPI / cash / bank). Sequential receipt
  /// number. If [extendTo] is given the subscription is renewed until then.
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
    DateTime? extendTo,
  }) async {
    final counterRef = FirestorePaths.counter('subscriptionReceipts');
    final paymentRef = FirestorePaths.subscriptionPayments().doc();
    late String receiptNo;

    await _db.runTransaction((tx) async {
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
        'status': 'received',
        'periodStart': periodStart == null ? null : Timestamp.fromDate(periodStart),
        'periodEnd': periodEnd == null ? null : Timestamp.fromDate(periodEnd),
        'paidAt': Timestamp.fromDate(paidAt),
        'recordedBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final cafeUpdate = <String, dynamic>{
        'subscription.lastPaymentAt': Timestamp.fromDate(paidAt),
        'subscription.paymentStatus': 'paid',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (extendTo != null) {
        cafeUpdate['subscription.expiryDate'] = Timestamp.fromDate(extendTo);
        cafeUpdate['subscription.status'] = SubscriptionStatus.active;
        if (periodStart != null) cafeUpdate['subscription.startDate'] = Timestamp.fromDate(periodStart);
      } else if (cafe.subscriptionStatus == SubscriptionStatus.pending) {
        cafeUpdate['subscription.status'] = SubscriptionStatus.active;
      }
      tx.update(FirestorePaths.cafe(cafe.id), cafeUpdate);
      tx.set(FirestorePaths.subscriptionHistory(cafe.id).doc(), {
        'action': 'payment',
        'receiptNo': receiptNo,
        'amount': amount,
        'method': method,
        'expiryDate': extendTo == null ? null : Timestamp.fromDate(extendTo),
        'by': _uid,
        'at': FieldValue.serverTimestamp(),
      });
    });

    await audit(
      'payment.record',
      cafeId: cafe.id,
      details: {'receiptNo': receiptNo, 'amount': amount, 'method': method, if (extendTo != null) 'extendedTo': Fmt.date(extendTo)},
    );
    return receiptNo;
  }

  // ---------------------------------------------------------------- logins

  /// Creates the Firebase Auth account for a login. Replaceable in tests.
  /// Uses a separate Firebase app instance, so the Super Admin stays signed
  /// in (creating an account signs that instance in as the new user).
  @visibleForTesting
  static Future<String> Function(String email, String password) createAuthAccount = _createAuthAccount;

  /// Changes a login's password with its current one. Replaceable in tests.
  @visibleForTesting
  static Future<void> Function(String email, String oldPassword, String newPassword) changeAuthPassword = _changeAuthPassword;

  static Future<FirebaseAuth> _helperAuth() async {
    const name = 'admin-helper';
    final app = Firebase.apps.where((a) => a.name == name).firstOrNull ?? await Firebase.initializeApp(name: name, options: Firebase.app().options);
    final auth = FirebaseAuth.instanceFor(app: app);
    if (kIsWeb) {
      try {
        await auth.setPersistence(Persistence.NONE);
      } catch (_) {}
    }
    return auth;
  }

  static Future<String> _createAuthAccount(String email, String password) async {
    final auth = await _helperAuth();
    try {
      final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      return cred.user!.uid;
    } finally {
      await auth.signOut();
    }
  }

  static Future<void> _changeAuthPassword(String email, String oldPassword, String newPassword) async {
    final auth = await _helperAuth();
    try {
      final cred = await auth.signInWithEmailAndPassword(email: email, password: oldPassword);
      await cred.user!.updatePassword(newPassword);
    } finally {
      await auth.signOut();
    }
  }

  /// Creates a cafe login (username + PIN, like flammywood / 123). Its role
  /// and cafe go to users/{uid}; firestore.rules accept them from there. The
  /// password goes only to Firebase Authentication – never stored or logged.
  Future<void> createLogin({
    required CafeSummary cafe,
    required String username,
    required String password,
    required String role, // manager (Manager + Captain view) | captain (kitchen only)
    String displayName = '',
  }) async {
    final user = username.trim().toLowerCase();
    final email = AppConfig.loginEmail(user);
    final uid = await createAuthAccount(email, AppConfig.loginPassword(user, password));
    await FirestorePaths.users().doc(uid).set({
      'email': email,
      'displayName': displayName.trim().isEmpty ? '${cafe.name} ($user)' : displayName.trim(),
      'role': role,
      'cafeId': cafe.id,
      'status': 'active',
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await audit('staff.create', cafeId: cafe.id, details: {'login': user, 'role': role});
  }

  /// Turns a login off (it can't use any cafe data) or on again.
  Future<void> setLoginActive(StaffMember member, bool active) async {
    await FirestorePaths.users().doc(member.uid).update({'status': active ? 'active' : 'disabled', 'updatedAt': FieldValue.serverTimestamp()});
    await audit('staff.access', cafeId: member.cafeId, details: {'login': member.loginName, 'access': active ? 'on' : 'off'});
  }

  /// New password for a login (needs its current password).
  Future<void> changeLoginPassword(StaffMember member, {required String current, required String next}) async {
    final login = member.loginName;
    await changeAuthPassword(member.email, AppConfig.loginPassword(login, current), AppConfig.loginPassword(login, next));
    await audit('staff.password', cafeId: member.cafeId, details: {'login': login});
  }

  // ---------------------------------------------------------- platform

  Future<void> savePlatformSettings(Map<String, dynamic> fields) async {
    await FirestorePaths.platformSettings().set({...fields, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await audit('platform.settings', details: {'fields': fields.keys.toList()});
  }

  // ---------------------------------------------------------------- audit

  /// Who did what, never with passwords or tokens.
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
