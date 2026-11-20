import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/core/auth/app_user.dart';
import 'package:pos_app/core/auth/auth_service.dart';
import 'package:pos_app/core/data/firestore_paths.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/receipt/print_station.dart';
import 'package:pos_app/features/receipt/print_station_host.dart';

void main() {
  late FakeFirebaseFirestore db;
  final svc = PrintStationService.instance;
  final order = {'billNo': '26-27/0042', 'tableNo': '4', 'totalPrice': 300.0, 'items': [{'name': 'Margherita', 'qty': 1, 'price': 300.0}]};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    FirestorePaths.overrideDb = db;
    FirestorePaths.setActiveCafe('A');
    AuthService.instance.currentUser = AppUser.resolve(uid: 'iphone', email: 'a@pos.example.com', displayName: 'Owner', claims: const {'role': 'manager', 'cafeId': 'A'});
    svc.enabled.value = false;
  });
  tearDown(() {
    FirestorePaths.overrideDb = null;
    FirestorePaths.setActiveCafe(null);
    AuthService.instance.currentUser = null;
    svc.enabled.value = false;
  });

  Future<Map<String, dynamic>> job(String id) async => (await db.doc('cafes/A/printJobs/$id').get()).data()!;

  group('service', () {
    test('a sent bill waits with a readable label', () async {
      final id = await svc.send(order: order, orderId: 'ORD1');
      final j = await job(id);
      expect(j['status'], 'pending');
      expect(j['label'], '26-27/0042 · 4');
      expect(j['createdBy'], 'iphone');
      expect((j['order'] as Map)['totalPrice'], 300.0);
    });

    test('a bill is taken by one station only', () async {
      final id = await svc.send(order: order, orderId: 'ORD1');
      expect(await svc.claim(id, 's1'), isNotNull);
      expect(await svc.claim(id, 's2'), isNull);
      expect((await job(id))['stationId'], 's1');
    });

    test('an old bill is not printed any more', () async {
      final id = await svc.send(order: order, orderId: 'ORD1');
      expect(await svc.claim(id, 's1', now: DateTime.now().add(const Duration(hours: 1))), isNull);
      expect((await job(id))['status'], 'expired');
    });

    test('put back, printed, result is reported', () async {
      final id = await svc.send(order: order, orderId: 'ORD1');
      await svc.claim(id, 's1');
      await svc.putBack(id);
      expect((await job(id))['status'], 'pending');
      await svc.claim(id, 's1');
      await svc.markPrinted(id);
      expect((await svc.waitForResult(id, timeout: const Duration(seconds: 1)))!.status, PrintJobStatus.printed);
    });

    test('finished bills older than a day are removed, waiting ones kept', () async {
      await db.doc('cafes/A/printJobs/old').set({'status': 'printed', 'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 2)))});
      await db.doc('cafes/A/printJobs/new').set({'status': 'printed', 'createdAt': Timestamp.now()});
      await db.doc('cafes/A/printJobs/wait').set({'status': 'pending', 'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 2)))});
      await svc.cleanUp();
      expect((await db.doc('cafes/A/printJobs/old').get()).exists, isFalse);
      expect((await db.doc('cafes/A/printJobs/new').get()).exists, isTrue);
      expect((await db.doc('cafes/A/printJobs/wait').get()).exists, isTrue);
    });

    test('the station is shown online for a few minutes after it was seen', () {
      final now = DateTime(2026, 11, 20, 12);
      expect(StationInfo({'lastSeen': Timestamp.fromDate(now.subtract(const Duration(minutes: 1)))}).isOnline(now), isTrue);
      expect(StationInfo({'lastSeen': Timestamp.fromDate(now.subtract(const Duration(minutes: 10)))}).isOnline(now), isFalse);
    });
  });

  group('station screen', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump();
      }
    }

    testWidgets('off: no bar, nothing printed', (t) async {
      final printed = <String>[];
      await svc.send(order: order, orderId: 'ORD1');
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: PrintStationHost(cafeId: 'A', printJob: (j) async => printed.add(j.orderId), child: const Text('dash')),
      ));
      await settle(t);
      expect(find.byKey(const Key('print-station-status')), findsNothing);
      expect(printed, isEmpty);
    });

    testWidgets('on: waits for Connect printer, then prints every waiting bill once', (t) async {
      SharedPreferences.setMockInitialValues({'flutter.cafe_pos_print_station_A': true});
      final printed = <String>[];
      final a = await svc.send(order: order, orderId: 'ORD1');
      final b = await svc.send(order: order, orderId: 'ORD2');
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PrintStationHost(
            cafeId: 'A',
            printJob: (j) async => printed.add(j.orderId),
            connectPrinter: (_) async {},
            child: const Text('dash'),
          ),
        ),
      ));
      await settle(t);
      expect(find.textContaining('2 bills waiting'), findsOneWidget);
      expect(printed, isEmpty);

      await t.tap(find.byKey(const Key('print-station-connect')));
      await settle(t);
      await settle(t);
      expect(printed..sort(), ['ORD1', 'ORD2']);
      expect((await job(a))['status'], 'printed');
      expect((await job(b))['status'], 'printed');
      expect(find.textContaining('2 printed'), findsOneWidget);
      expect(find.text('dash'), findsOneWidget);
    });

    testWidgets('printer trouble: the bill goes back to waiting', (t) async {
      SharedPreferences.setMockInitialValues({'flutter.cafe_pos_print_station_A': true});
      final id = await svc.send(order: order, orderId: 'ORD1');
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PrintStationHost(
            cafeId: 'A',
            printJob: (j) async => throw Exception('printer off'),
            connectPrinter: (_) async {},
            child: const Text('dash'),
          ),
        ),
      ));
      await settle(t);
      await t.tap(find.byKey(const Key('print-station-connect')));
      await settle(t);
      await settle(t);
      expect((await job(id))['status'], 'pending');
      expect(find.byKey(const Key('print-station-connect')), findsOneWidget);
    });
  });
}
