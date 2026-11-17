import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/auth/app_user.dart';
import 'package:pos_app/core/auth/auth_service.dart';
import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/admin/admin_data.dart';
import 'package:pos_app/features/admin/admin_service.dart';
import 'package:pos_app/features/admin/payments_screen.dart';
import 'package:pos_app/features/subscription/pay_now_dialog.dart';
import 'package:pos_app/features/subscription/upi_payment.dart';

import 'layout_test.dart' as lt;

void main() {
  group('UPI helpers', () {
    test('UPI ID', () {
      expect(isValidUpiId('cafepos@okaxis'), isTrue);
      expect(isValidUpiId('cafe.pos-1@ybl'), isTrue);
      expect(isValidUpiId('cafepos'), isFalse);
      expect(isValidUpiId('cafe pos@okaxis'), isFalse);
      expect(isValidUpiId('a@b'), isFalse);
    });

    test('UTR is 12 digits; spaces and dashes ignored', () {
      expect(normalizeUtr('4123 5678 9012'), '412356789012');
      expect(normalizeUtr('4123-5678-9012'), '412356789012');
      expect(normalizeUtr('41235678901'), isNull);
      expect(normalizeUtr('41235678901A'), isNull);
    });

    test('pay link has the amount, INR and a safe note', () {
      final link = upiPayLink(
        payee: const UpiPayee(upiId: 'owner@okaxis', payeeName: 'Cafe POS Pvt'),
        amount: 899,
        note: upiNote('Flammy Wood & Co.', 'Standard', 'monthly'),
      );
      expect(link, startsWith('upi://pay?pa=owner@okaxis&pn=Cafe%20POS%20Pvt&am=899.00&cu=INR&tn='));
      expect(link, contains('CafePOS%20Flammy%20Wood%20Co%20Standard%20monthly'));
      expect(upiNote('A' * 80, 'Standard', 'monthly').length, lessThanOrEqualTo(50));
    });

    test('renewal counts from the current end date, or from today if expired', () {
      final now = DateTime(2026, 11, 17, 10);
      expect(renewedUntil(currentExpiry: DateTime(2026, 11, 25), cycle: 'monthly', now: now), DateTime(2026, 12, 25));
      expect(renewedUntil(currentExpiry: DateTime(2026, 11, 1), cycle: 'yearly', now: now), DateTime(2027, 11, 17, 10));
      expect(renewedUntil(cycle: 'monthly', now: now), DateTime(2026, 12, 17, 10));
    });
  });

  group('approve / reject a claim (Super Admin)', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      FirestorePaths.overrideDb = db;
      await db.doc('cafes/A').set({
        'name': 'Cafe A',
        'status': 'active',
        'subscription': {'status': 'trial', 'billingCycle': 'trial', 'planName': 'Free Trial', 'expiryDate': DateTime(2026, 11, 1)},
      });
      await db.doc('paymentClaims/A').set({
        'cafeId': 'A', 'cafeName': 'Cafe A', 'utr': '412356789012', 'amount': 899,
        'planId': 'std', 'planName': 'Standard', 'cycle': 'monthly', 'status': 'pending',
      });
      await db.doc('paymentRefs/412356789012').set({'cafeId': 'A'});
    });
    tearDown(() => FirestorePaths.overrideDb = null);

    Future<PaymentClaim> claim() async => PaymentClaim('A', (await db.doc('paymentClaims/A').get()).data()!);
    Future<CafeSummary> cafe() async => CafeSummary('A', (await db.doc('cafes/A').get()).data()!);

    test('approve: payment recorded, cafe renewed on the paid plan, claim closed', () async {
      final until = DateTime(2026, 12, 17);
      final no = await AdminService.instance.recordPayment(
        cafe: await cafe(), amount: 899, method: 'UPI', referenceId: '412356789012',
        paidAt: DateTime(2026, 11, 17), extendTo: until, claim: await claim(),
      );
      expect(no, 'RCPT-0001');
      final sub = (await db.doc('cafes/A').get()).data()!['subscription'] as Map;
      expect(sub['status'], 'active');
      expect(sub['planName'], 'Standard');
      expect(sub['billingCycle'], 'monthly');
      expect(sub['amount'], 899);
      final c = await claim();
      expect(c.isApproved, isTrue);
      expect(c.receiptNo, 'RCPT-0001');
      final pay = (await db.collection('subscriptionPayments').get()).docs.single.data();
      expect(pay['referenceId'], '412356789012');
      expect(pay['source'], 'upi-claim');
    });

    test('reject: subscription untouched, reason kept, UTR freed', () async {
      await AdminService.instance.rejectClaim(await claim(), reason: 'Not in bank');
      final c = await claim();
      expect(c.isRejected, isTrue);
      expect(c.rejectReason, 'Not in bank');
      expect((await db.doc('paymentRefs/412356789012').get()).exists, isFalse);
      expect(((await db.doc('cafes/A').get()).data()!['subscription'] as Map)['status'], 'trial');
      final h = (await db.collection('cafes/A/subscriptionHistory').get()).docs.single.data();
      expect(h['action'], 'claim_rejected');
    });
  });

  group('screens', () {
    late FakeFirebaseFirestore db;
    setUpAll(lt.loadInter);
    setUp(() async {
      db = FakeFirebaseFirestore();
      FirestorePaths.overrideDb = db;
      AuthService.instance.currentUser =
          AppUser.resolve(uid: 'mA', email: 'cafea@pos.example.com', displayName: 'Cafe A', claims: const {'role': 'manager', 'cafeId': 'A'});
      await db.doc('platform/payee').set({'upiId': 'owner@okaxis', 'payeeName': 'Cafe POS'});
      await db.doc('plans/std').set({'name': 'Standard', 'tier': 'standard', 'monthlyPrice': 899, 'yearlyPrice': 8999});
      await db.doc('plans/trial').set({'name': 'Free Trial', 'tier': 'trial', 'trialDays': 14});
    });
    tearDown(() {
      FirestorePaths.overrideDb = null;
      AuthService.instance.currentUser = null;
    });

    for (final s in {'phone': lt.sizes['phone']!, 'desktop': lt.sizes['desktop']!}.entries) {
      testWidgets('pay now: QR with the price, then "I\'ve paid" sends a pending claim · ${s.key}', (t) async {
        await lt.pumpAt(
          t,
          s.value,
          Builder(
            builder: (c) => Center(
              child: TextButton(onPressed: () => showPayNowDialog(c, cafeId: 'A', cafeName: 'Cafe A'), child: const Text('open')),
            ),
          ),
          AppTheme.light(),
        );
        await t.tap(find.text('open'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('pay-qr')), findsOneWidget);
        expect(find.text('₹899'), findsOneWidget);
        expect(find.text('Free Trial'), findsNothing, reason: 'the trial is not a plan to pay for');

        await t.enterText(find.byKey(const Key('claim-utr')), '4123 5678 9012');
        await t.ensureVisible(find.byKey(const Key('claim-send')));
        await t.tap(find.byKey(const Key('claim-send')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pumpAndSettle();
        final claim = await t.runAsync(() => db.doc('paymentClaims/A').get());
        expect(claim!.data()!['status'], 'pending');
        expect(claim.data()!['utr'], '412356789012');
        expect(claim.data()!['amount'], 899);
        expect(find.text('Payment received – being verified'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('payments screen lists claims to approve · ${s.key}', (t) async {
        final data = AdminDataController.fixed(AdminData(
          loading: false,
          cafes: [CafeSummary('A', const {'name': 'Cafe A', 'status': 'active'})],
          claims: [PaymentClaim('A', const {'cafeName': 'Cafe A', 'utr': '412356789012', 'amount': 899, 'planName': 'Standard', 'cycle': 'monthly'})],
        ));
        await lt.pumpAt(t, s.value, PaymentsScreen(data: data), AppTheme.light());
        expect(find.text('Waiting for approval (1)'), findsOneWidget);
        await t.tap(find.byKey(const Key('claim-approve-A')));
        await t.pumpAndSettle();
        expect(find.text('Approve payment · Cafe A'), findsOneWidget);
        expect(find.textContaining('Never approve from a screenshot'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
