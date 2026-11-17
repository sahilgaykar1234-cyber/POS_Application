import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/auth/auth_service.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/services/audit_service.dart';
import '../admin/admin_models.dart';
import 'upi_payment.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// Thrown when a claim can't be sent; [message] is ready to show.
class ClaimException implements Exception {
  const ClaimException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a cafe's Manager needs to pay the subscription: where to pay, the
/// plans and the cafe's own claim. A claim never changes the subscription:
/// firestore.rules let the cafe only create a "pending" claim, and only the
/// Super Admin can approve it (after the money is in the bank).
class RenewalService {
  RenewalService._();
  static final instance = RenewalService._();

  Stream<UpiPayee> watchPayee() => FirestorePaths.platformPayee().snapshots().map((d) => UpiPayee.fromMap(d.data()));

  Stream<PaymentClaim?> watchClaim(String cafeId) =>
      FirestorePaths.paymentClaim(cafeId).snapshots().map((d) => d.exists ? PaymentClaim(d.id, d.data()!) : null);

  /// Paid plans a cafe can choose (active, not the free trial), cheapest first.
  Stream<List<SubscriptionPlan>> watchPaidPlans() => FirestorePaths.plans().snapshots().map((s) {
    final list = s.docs
        .map((d) => SubscriptionPlan(d.id, d.data()))
        .where((p) => p.isActive && p.tier != PlanTier.trial && (p.monthlyPrice > 0 || p.yearlyPrice > 0))
        .toList();
    list.sort((a, b) => a.monthlyPrice.compareTo(b.monthlyPrice));
    return list;
  });

  /// Sends "we paid [amount] by UPI, reference [utr]". The claim and the UTR
  /// are written together; the rules refuse a UTR that was used before.
  Future<void> submitClaim({
    required String cafeId,
    required String cafeName,
    required String utr,
    required double amount,
    required SubscriptionPlan plan,
    required String cycle,
  }) async {
    final ref = normalizeUtr(utr);
    if (ref == null) throw ClaimException(tr('Enter the 12-digit UPI reference number (UTR) from your UPI app.'));
    final user = AuthService.instance.currentUser;
    if (user == null) throw ClaimException(tr('Please sign in again.'));

    final batch = FirestorePaths.db.batch();
    batch.set(FirestorePaths.paymentClaim(cafeId), {
      'cafeId': cafeId,
      'cafeName': cafeName,
      'utr': ref,
      'amount': amount,
      'planId': plan.id,
      'planName': plan.name,
      'cycle': cycle,
      'status': ClaimStatus.pending,
      'submittedBy': user.uid,
      'submittedAt': FieldValue.serverTimestamp(),
    });
    batch.set(FirestorePaths.paymentRef(ref), {'cafeId': cafeId, 'createdAt': FieldValue.serverTimestamp()});
    try {
      await batch.commit().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ClaimException(tr('No internet connection. It will be sent automatically when you are back online.'));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw ClaimException(tr('This UPI reference number has already been used. Please check it in your UPI app.'));
      }
      throw ClaimException(tr('Could not send it ({0}). Please try again.', [e.code]));
    }
    unawaited(AuditService.instance.log('payment.claim', cafeId: cafeId, details: {'utr': ref, 'amount': amount, 'plan': plan.name, 'cycle': cycle}));
  }
}
