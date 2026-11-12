import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/auth/app_user.dart';
import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/admin/admin_data.dart';
import 'package:pos_app/features/admin/admin_dialogs.dart';
import 'package:pos_app/features/admin/admin_service.dart';
import 'package:pos_app/features/admin/cafe_detail_screen.dart';
import 'package:pos_app/features/admin/cafes_screen.dart';
import 'package:pos_app/features/admin/payments_screen.dart';
import 'package:pos_app/features/admin/staff_screen.dart';
import 'package:pos_app/features/admin/super_admin_shell.dart';

import 'layout_test.dart' as lt;

final now = DateTime(2026, 11, 12, 12);
Timestamp ts(DateTime d) => Timestamp.fromDate(d);

List<CafeSummary> sampleCafes() => [
      CafeSummary('flammy', {
        'name': 'Flammy Wood',
        'status': 'active',
        'ownerName': 'Sahil',
        'city': 'Surat',
        'createdAt': ts(DateTime(2026, 9, 1)),
        'subscription': {'status': 'active', 'planName': 'Standard', 'planId': 'std', 'billingCycle': 'monthly', 'amount': 999, 'expiryDate': ts(DateTime(2026, 11, 15)), 'paymentStatus': 'paid'},
      }),
      CafeSummary('forno', {
        'name': 'Pizza La Forno',
        'status': 'active',
        'createdAt': ts(DateTime(2026, 11, 10)),
        'subscription': {'status': 'trial', 'planName': 'Free Trial', 'billingCycle': 'trial', 'amount': 0, 'expiryDate': ts(DateTime(2026, 11, 24))},
      }),
      CafeSummary('yearly', {
        'name': 'Yearly Cafe',
        'status': 'active',
        'createdAt': ts(DateTime(2026, 6, 1)),
        'subscription': {'status': 'active', 'billingCycle': 'yearly', 'amount': 12000, 'expiryDate': ts(DateTime(2027, 6, 1))},
      }),
      CafeSummary('old', {
        'name': 'Expired Cafe',
        'status': 'active',
        'createdAt': ts(DateTime(2025, 1, 1)),
        'subscription': {'status': 'active', 'amount': 500, 'expiryDate': ts(DateTime(2026, 11, 1))},
      }),
      CafeSummary('off', {'name': 'Closed Cafe', 'status': 'inactive', 'createdAt': ts(DateTime(2025, 2, 1))}),
    ];

List<StaffMember> sampleStaff() => [
      StaffMember('u1', {'email': 'flammywood@pos.example.com', 'role': 'manager', 'cafeId': 'flammy', 'displayName': 'Flammy Wood (shared login)', 'status': 'active'}),
      StaffMember('u2', {'email': 'laforno@pos.example.com', 'role': 'manager', 'cafeId': 'forno', 'status': 'active'}),
      StaffMember('u3', {'email': 'cook@x.com', 'role': 'captain', 'cafeId': 'flammy', 'status': 'disabled'}),
      StaffMember('sa', {'email': 'owner@x.com', 'role': 'superAdmin'}),
    ];

List<SubscriptionPayment> samplePayments() => [
      SubscriptionPayment('p1', {'cafeId': 'flammy', 'cafeName': 'Flammy Wood', 'receiptNo': 'RCPT-0001', 'amount': 999, 'method': 'UPI', 'planName': 'Standard', 'paidAt': ts(DateTime(2026, 10, 15))}),
      SubscriptionPayment('p2', {'cafeId': 'yearly', 'cafeName': 'Yearly Cafe', 'receiptNo': 'RCPT-0002', 'amount': 12000, 'method': 'Bank Transfer', 'paidAt': ts(DateTime(2026, 6, 1))}),
      SubscriptionPayment('p3', {'cafeId': 'flammy', 'amount': 999, 'method': 'Cash', 'status': 'refunded', 'paidAt': ts(DateTime(2026, 11, 2))}),
    ];

AdminData sampleData() => AdminData(
      cafes: sampleCafes(),
      staff: sampleStaff(),
      plans: [
        SubscriptionPlan('trial', {'name': 'Free Trial', 'tier': 'trial', 'trialDays': 14}),
        SubscriptionPlan('std', {'name': 'Standard', 'tier': 'standard', 'monthlyPrice': 999, 'yearlyPrice': 9999, 'maxStaff': 5, 'features': ['POS', 'Kitchen', 'Reports']}),
        SubscriptionPlan('legacy', {'name': 'Old yearly', 'billingCycle': 'yearly', 'price': 5000}),
      ],
      payments: samplePayments(),
      platform: PlatformSettings(const {'platformName': 'Cafe POS', 'reminderDays': 7}),
      loading: false,
    );

void main() {
  group('platform stats (real data only)', () {
    test('counts, MRR from running paid plans (yearly / 12), trial not revenue', () {
      final s = PlatformStats.of(cafes: sampleCafes(), staff: sampleStaff(), payments: samplePayments(), now: now);
      expect(s.totalCafes, 5);
      expect(s.activeCafes, 4);
      expect(s.inactiveCafes, 1);
      expect(s.trialCafes, 1);
      expect(s.managers, 2);
      expect(s.captains, 0, reason: 'the only captain login is turned off');
      expect(s.activeSubscriptions, 2);
      expect(s.expiredSubscriptions, 1);
      expect(s.mrr, 999 + 1000);
      expect(s.hasRevenueData, isTrue);
      expect(s.totalCollected, 999 + 12000, reason: 'refunds are not collected money');
      expect(s.paymentCount, 2);
    });

    test('no plans and no payments: nothing invented', () {
      final s = PlatformStats.of(cafes: [CafeSummary('a', {'name': 'A', 'status': 'active'})], staff: const [], payments: const [], now: now);
      expect(s.hasRevenueData, isFalse);
      expect(s.mrr, 0);
      expect(s.paymentCount, 0);
      expect(s.bySubState[SubState.none], 1);
    });

    test('monthly series', () {
      final series = monthlySeries(sampleCafes(), dateOf: (c) => c.createdAt, now: now);
      expect(series.length, 6);
      expect(series.first.$1, DateTime(2026, 6));
      expect(series.first.$2, 1);
      expect(series.last.$2, 1);
    });
  });

  group('alerts', () {
    final alerts = computeAlerts(cafes: sampleCafes(), staff: sampleStaff(), now: now, settings: PlatformSettings(const {'reminderDays': 7}));
    String titles(AlertLevel l) => alerts.where((a) => a.level == l).map((a) => a.title).join(' | ');

    test('expired is critical; expiring within reminder days is a warning', () {
      expect(titles(AlertLevel.critical), contains('Expired Cafe: subscription expired'));
      expect(titles(AlertLevel.warning), contains('Flammy Wood: subscription ends in 3 days'));
      expect(titles(AlertLevel.warning), isNot(contains('Pizza La Forno: trial')), reason: 'trial ends in 12 days');
      expect(alerts.first.level, AlertLevel.critical);
    });

    test('cafes without a login, inactive cafes, new cafes', () {
      expect(titles(AlertLevel.warning), contains('Yearly Cafe: no login'));
      expect(titles(AlertLevel.info), contains('Closed Cafe is inactive'));
      expect(titles(AlertLevel.info), contains('New cafe: Pizza La Forno'));
    });
  });

  group('filters', () {
    final d = sampleData();
    test('cafes', () {
      expect(filterCafes(d.cafes, search: 'surat', now: now).single.id, 'flammy');
      expect(filterCafes(d.cafes, status: 'inactive', now: now).single.id, 'off');
      expect(filterCafes(d.cafes, sub: SubState.expired, now: now).single.id, 'old');
      expect(filterCafes(d.cafes, sort: CafeSort.expiry, now: now).first.id, 'old');
      expect(filterCafes(d.cafes, sort: CafeSort.newest, now: now).first.id, 'forno');
    });
    test('staff (super admin never listed)', () {
      expect(filterStaff(d.staff, d).length, 3);
      expect(filterStaff(d.staff, d, cafeId: 'flammy').length, 2);
      expect(filterStaff(d.staff, d, status: 'off').single.uid, 'u3');
      expect(filterStaff(d.staff, d, search: 'la forno').single.uid, 'u2');
      expect(d.staff.first.isSharedCafeLogin, isTrue);
      expect(d.staff.first.loginName, 'flammywood');
    });
    test('payments', () {
      expect(filterPayments(d.payments).first.id, 'p3');
      expect(filterPayments(d.payments, cafeId: 'flammy').length, 2);
      expect(filterPayments(d.payments, method: 'UPI').single.id, 'p1');
      expect(filterPayments(d.payments, range: DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31))).single.id, 'p1');
    });
    test('old single-price plans still read', () {
      final legacy = d.plans.last;
      expect(legacy.yearlyPrice, 5000);
      expect(legacy.monthlyPrice, 0);
      expect(d.plans[1].priceLabel, '₹999/mo · ₹9,999/yr');
      expect(d.plans.first.priceLabel, 'Free · 14 days');
    });
  });

  group('screens', () {
    setUpAll(lt.loadInter);
    setUp(() {
      FirestorePaths.overrideDb = FakeFirebaseFirestore();
      FirestorePaths.setActiveCafe(null);
    });
    tearDown(() => FirestorePaths.overrideDb = null);

    for (final theme in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
      for (final s in lt.sizes.entries) {
        testWidgets('Super Admin: every section · ${s.key} · ${theme.key}', (t) async {
          final controller = AdminDataController.fixed(sampleData());
          await lt.pumpAt(t, s.value, SuperAdminShell(controller: controller), theme.value);
          expect(find.text('Platform overview'), findsOneWidget);
          expect(t.takeException(), isNull);
          for (final label in ['Cafes', 'Staff', 'Subscriptions', 'Payments', 'Alerts', 'Activity', 'Settings']) {
            final target = find.text(label);
            if (target.evaluate().isEmpty) {
              await t.tap(find.text('More'));
              await t.pumpAndSettle();
            }
            await t.tap(find.text(label).last);
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull, reason: label);
          }
        });

        testWidgets('Cafe details: every tab · ${s.key} · ${theme.key}', (t) async {
          final controller = AdminDataController.fixed(sampleData());
          await lt.pumpAt(
            t,
            s.value,
            CafeDetailScreen(
              cafeId: 'flammy',
              data: controller,
              settingsStream: Stream.value(const {'shopName': 'Flammy Wood', 'dayEndsAt': '05:00'}),
              auditStream: Stream.value([
                {'action': 'subscription.set', 'cafeId': 'flammy', 'actorRole': 'superAdmin', 'details': {'plan': 'Standard'}, 'at': Timestamp.now()},
              ]),
              historyStream: Stream.value([
                {'action': 'assigned', 'planName': 'Standard', 'amount': 999, 'expiryDate': Timestamp.now(), 'at': Timestamp.now()},
              ]),
              ops: Future.value(const CafeOpsSummary(categories: 9, menuItems: 56, availableItems: 54, ordersToday: 12, orders30d: 300, billed30d: 120000, lastOrderAt: null)),
            ),
            theme.value,
          );
          for (final tab in CafeDetailScreen.tabs) {
            await t.tap(find.text(tab));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: tab);
          }
          expect(find.text('Up to 5 staff'), findsNothing);
        });
      }
    }

    testWidgets('staff list: on/off switch and password menu (no commands)', (t) async {
      final controller = AdminDataController.fixed(sampleData());
      await lt.pumpAt(t, lt.sizes['desktop']!, StaffScreen(data: controller), AppTheme.light());
      expect(find.byKey(const Key('login-switch-u1')), findsOneWidget);
      expect(find.textContaining('admin.js'), findsNothing);
      await t.tap(find.byKey(const Key('login-switch-u1')));
      await t.pumpAndSettle();
      expect(find.text('Turn off "flammywood"?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('payments screen says when nothing is recorded', (t) async {
      final controller = AdminDataController.fixed(const AdminData(loading: false));
      await lt.pumpAt(t, lt.sizes['phone']!, PaymentsScreen(data: controller), AppTheme.light());
      expect(find.text('No payments recorded yet'), findsOneWidget);
    });
  });

  group('dialogs open, save and write (fake Firestore)', () {
    late FakeFirebaseFirestore db;
    setUpAll(lt.loadInter);
    setUp(() {
      db = FakeFirebaseFirestore();
      FirestorePaths.overrideDb = db;
    });
    tearDown(() => FirestorePaths.overrideDb = null);

    Future<void> open(WidgetTester t, Size size, Future<void> Function(BuildContext) show) async {
      await lt.pumpAt(
        t,
        size,
        Builder(builder: (c) => Center(child: TextButton(onPressed: () => show(c), child: const Text('open')))),
        AppTheme.light(),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    for (final s in {'phone': lt.sizes['phone']!, 'desktop': lt.sizes['desktop']!}.entries) {
      testWidgets('new plan · ${s.key}', (t) async {
        await open(t, s.value, (c) => showPlanForm(c));
        expect(find.byKey(const Key('plan-name')), findsOneWidget);
        await t.enterText(find.byKey(const Key('plan-name')), 'Gold');
        await t.enterText(find.widgetWithText(TextField, 'Monthly price'), '1199');
        await t.tap(find.byKey(const Key('plan-save')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        final plans = await t.runAsync(() => db.collection('plans').get());
        expect(plans!.docs.single.data()['name'], 'Gold');
        expect(plans.docs.single.data()['monthlyPrice'], 1199);
      });

      testWidgets('new cafe with a trial · ${s.key}', (t) async {
        String? id;
        await open(t, s.value, (c) async => id = await showCafeForm(c, platform: PlatformSettings(const {'trialDays': 14})));
        await t.enterText(find.widgetWithText(TextFormField, 'Cafe name *'), 'Chai Point');
        await t.enterText(find.widgetWithText(TextFormField, 'City'), 'Surat');
        await t.ensureVisible(find.byKey(const Key('cafe-save')));
        await t.tap(find.byKey(const Key('cafe-save')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        expect(id, isNotNull);
        final cafe = await t.runAsync(() => db.collection('cafes').doc(id).get());
        expect(cafe!.data()!['name'], 'Chai Point');
        expect(cafe.data()!['subscription']['status'], 'trial');
        final settings = await t.runAsync(() => db.doc('cafes/$id/settings/business').get());
        expect(settings!.data()!['dayEndsAt'], '05:00');
      });

      testWidgets('assign plan, renew, record payment · ${s.key}', (t) async {
        await t.runAsync(() => db.collection('cafes').doc('flammy').set(sampleCafes().first.data));
        final cafe = sampleCafes().first;
        final plans = sampleData().plans;
        await open(t, s.value, (c) => showAssignPlan(c, cafe, plans));
        await t.tap(find.byKey(const Key('assign-save')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        var doc = await t.runAsync(() => db.collection('cafes').doc('flammy').get());
        expect(doc!.data()!['subscription']['planName'], 'Standard');

        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        await open(t, s.value, (c) => showRenew(c, cafe));
        await t.tap(find.text('Renew').last);
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        final history = await t.runAsync(() => db.collection('cafes/flammy/subscriptionHistory').get());
        expect(history!.docs.length, 2);

        await open(t, s.value, (c) => showRecordPayment(c, [cafe], cafe: cafe));
        await t.enterText(find.byKey(const Key('payment-amount')), '999');
        await t.ensureVisible(find.byKey(const Key('payment-save')));
        await t.tap(find.byKey(const Key('payment-save')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        final pays = await t.runAsync(() => db.collection('subscriptionPayments').get());
        expect(pays!.docs.single.data()['receiptNo'], 'RCPT-0001');
        expect(t.takeException(), isNull);
      });
    }

    test('recommended plans are added once', () async {
      expect(await AdminService.instance.addRecommendedPlans(const []), 4);
      final first = (await db.collection('plans').get()).docs.map((d) => SubscriptionPlan(d.id, d.data())).toList();
      expect(first.map((p) => p.name).toSet(), {'Free Trial', 'Basic', 'Standard', 'Premium'});
      expect(first.firstWhere((p) => p.name == 'Basic').priceLabel, '₹499/mo · ₹4,999/yr');
      expect(first.firstWhere((p) => p.name == 'Free Trial').trialDays, 14);
      expect(await AdminService.instance.addRecommendedPlans(first), 0);
    });
  });

  testWidgets('plans: edit, hide and delete from the card', (t) async {
    final db = FakeFirebaseFirestore();
    FirestorePaths.overrideDb = db;
    addTearDown(() => FirestorePaths.overrideDb = null);
    await lt.loadInter();
    await t.runAsync(() => db.collection('plans').doc('std').set({'name': 'Standard', 'tier': 'standard', 'monthlyPrice': 899}));
    final data = AdminDataController.fixed(AdminData(
      cafes: sampleCafes(),
      plans: [SubscriptionPlan('std', const {'name': 'Standard', 'tier': 'standard', 'monthlyPrice': 899})],
      loading: false,
    ));
    for (final size in [lt.sizes['phone']!, lt.sizes['desktop']!]) {
      await lt.pumpAt(t, size, SuperAdminShell(controller: data), AppTheme.light());
      await t.tap(find.text('Subscriptions').last);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Plans ('));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('plan-edit-std')), findsOneWidget);
      expect(find.byKey(const Key('plan-visibility-std')), findsOneWidget);
      expect(find.byKey(const Key('plan-delete-std')), findsOneWidget);
      expect(t.takeException(), isNull);
    }
    await t.tap(find.byKey(const Key('plan-edit-std')));
    await t.pumpAndSettle();
    expect(find.text('Edit plan'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('plan-delete-std')));
    await t.pumpAndSettle();
    expect(find.textContaining('1 cafe use this plan'), findsOneWidget, reason: 'Flammy Wood is on Standard');
    await t.tap(find.text('Delete plan'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    final left = await t.runAsync(() => db.collection('plans').get());
    expect(left!.docs, isEmpty);
    final log = await t.runAsync(() => db.collection('auditLogs').get());
    expect(log!.docs.single.data()['action'], 'plan.delete');
  });

  group('logins created in the panel', () {
    late FakeFirebaseFirestore db;
    final created = <String, String>{};
    setUpAll(lt.loadInter);
    setUp(() async {
      db = FakeFirebaseFirestore();
      FirestorePaths.overrideDb = db;
      created.clear();
      AdminService.createAuthAccount = (email, password) async {
        if (email == 'taken@pos.example.com') {
          throw FirebaseAuthException(code: 'email-already-in-use');
        }
        created[email] = password;
        return 'uid-${email.split('@').first}';
      };
      await db.collection('cafes').doc('flammy').set(sampleCafes().first.data);
    });
    tearDown(() => FirestorePaths.overrideDb = null);

    test('validation', () {
      expect(validateNewLogin('ab', '123', '123'), contains('Username'));
      expect(validateNewLogin('flammy wood', '123', '123'), contains('Username'));
      expect(validateNewLogin('counter1', '12', '12'), contains('at least 3'));
      expect(validateNewLogin('counter1', '123', '124'), contains("don't match"));
      expect(validateNewLogin('Counter.1', '123', '123'), isNull);
    });

    for (final s in {'phone': lt.sizes['phone']!, 'desktop': lt.sizes['desktop']!}.entries) {
      testWidgets('add login from the cafe page · ${s.key}', (t) async {
        await lt.pumpAt(
          t,
          s.value,
          Builder(builder: (c) => Center(child: TextButton(onPressed: () => showAddLogin(c, sampleCafes().first), child: const Text('open')))),
          AppTheme.light(),
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.enterText(find.byKey(const Key('login-username')), 'Counter1');
        await t.enterText(find.byKey(const Key('login-password')), '1234');
        await t.enterText(find.byKey(const Key('login-confirm')), '1234');
        await t.tap(find.text('Kitchen only'));
        await t.ensureVisible(find.byKey(const Key('login-save')));
        await t.tap(find.byKey(const Key('login-save')));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pumpAndSettle();
        // Same email/password scheme as the login screen and the admin script.
        expect(created, {'counter1@pos.example.com': 'cafepos-1234'});
        final user = await t.runAsync(() => db.collection('users').doc('uid-counter1').get());
        expect(user!.data()!['role'], 'captain');
        expect(user.data()!['cafeId'], 'flammy');
        expect(user.data()!['status'], 'active');
        expect(user.data()!.values.join(' '), isNot(contains('1234')), reason: 'password never stored');
        expect(find.byKey(const Key('login-username')), findsNothing, reason: 'dialog closed');
      });
    }

    testWidgets('a taken username explains itself', (t) async {
      await lt.pumpAt(
        t,
        lt.sizes['desktop']!,
        Builder(builder: (c) => Center(child: TextButton(onPressed: () => showAddLogin(c, sampleCafes().first), child: const Text('open')))),
        AppTheme.light(),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('login-username')), 'taken');
      await t.enterText(find.byKey(const Key('login-password')), '1234');
      await t.enterText(find.byKey(const Key('login-confirm')), '1234');
      await t.tap(find.byKey(const Key('login-save')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text('The username "taken" is already taken. Please choose another.'), findsOneWidget);
    });

    test('turn off / on and change password', () async {
      final m = StaffMember('u9', {'email': 'counter1@pos.example.com', 'role': 'manager', 'cafeId': 'flammy', 'status': 'active'});
      await db.collection('users').doc('u9').set(m.data);
      await AdminService.instance.setLoginActive(m, false);
      expect((await db.collection('users').doc('u9').get()).data()!['status'], 'disabled');
      String? seen;
      AdminService.changeAuthPassword = (email, old, next) async => seen = '$email $old $next';
      await AdminService.instance.changeLoginPassword(m, current: '123', next: '999');
      expect(seen, 'counter1@pos.example.com cafepos-123 cafepos-999');
    });

    test('roles: claims first, panel logins from users/{uid}, never Super Admin from a document', () {
      AppUser r({Map<String, dynamic>? claims, Map<String, dynamic>? doc}) =>
          AppUser.resolve(uid: 'x', email: 'x@pos.example.com', displayName: null, claims: claims, userDoc: doc);
      expect(r(claims: {'role': 'manager', 'cafeId': 'A'}).cafeId, 'A');
      final panel = r(doc: {'role': 'captain', 'cafeId': 'B', 'status': 'active'});
      expect(panel.role, UserRole.captain);
      expect(panel.cafeId, 'B');
      expect(r(doc: {'role': 'superAdmin'}).role, isNull);
      expect(r(doc: {'role': 'manager', 'cafeId': 'A', 'status': 'disabled'}).loginDisabled, isTrue);
      expect(r(claims: {'role': 'manager', 'cafeId': 'A'}, doc: {'status': 'disabled'}).loginDisabled, isTrue);
      expect(r(claims: {'role': 'superAdmin'}, doc: {'status': 'disabled'}).loginDisabled, isFalse);
    });
  });
}
