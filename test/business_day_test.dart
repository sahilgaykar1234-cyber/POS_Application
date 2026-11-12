import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/business_day.dart';
import 'package:pos_app/features/manager/sales_stats.dart';
import 'package:pos_app/features/orders/order_model.dart';
import 'package:pos_app/features/settings/business_settings.dart';

PosOrder o(String id, DateTime at, {double total = 100, String pay = 'paid_cash'}) =>
    PosOrder(id, {'createdAt': Timestamp.fromDate(at), 'totalPrice': total, 'paymentStatus': pay, 'status': 'completed'});

void main() {
  tearDown(() => BusinessDay.setCutoff(BusinessDay.defaultCutoffMinutes));

  group('BusinessDay (shop open 7 PM – 2 AM, day ends 5 AM)', () {
    test('a night past midnight is one day', () {
      expect(BusinessDay.dateOf(DateTime(2026, 11, 12, 19)), DateTime(2026, 11, 12));
      expect(BusinessDay.dateOf(DateTime(2026, 11, 13, 1, 30)), DateTime(2026, 11, 12));
      expect(BusinessDay.dateOf(DateTime(2026, 11, 13, 4, 59)), DateTime(2026, 11, 12));
      expect(BusinessDay.dateOf(DateTime(2026, 11, 13, 5)), DateTime(2026, 11, 13));
      expect(BusinessDay.today(DateTime(2026, 11, 13, 2)), (DateTime(2026, 11, 12, 5), DateTime(2026, 11, 13, 5)));
      expect(BusinessDay.nextChange(DateTime(2026, 11, 12, 22)), DateTime(2026, 11, 13, 5));
    });

    test('month and year boundaries', () {
      expect(BusinessDay.dateOf(DateTime(2026, 12, 1, 1)), DateTime(2026, 11, 30));
      expect(BusinessDay.dateOf(DateTime(2027, 1, 1, 2)), DateTime(2026, 12, 31));
    });

    test('midnight cutoff behaves like the calendar', () {
      BusinessDay.setCutoff(0);
      expect(BusinessDay.dateOf(DateTime(2026, 11, 13, 1)), DateTime(2026, 11, 13));
    });

    test('labels and settings', () {
      expect(BusinessDay.label(300), '5:00 AM');
      expect(BusinessDay.label(0), '12:00 AM');
      expect(BusinessDay.parse('02:30'), 150);
      expect(BusinessDay.parse('25:00'), isNull);
      expect(BusinessDay.format(150), '02:30');
      expect(BusinessSettings(const {}).dayEndsAtMinutes, 300);
      expect(BusinessSettings(const {'dayEndsAt': '03:00'}).dayEndsAtMinutes, 180);
      expect(BusinessSettings(const {'dayEndsAt': '18:00'}).dayEndsAtMinutes, 300); // PM not allowed
    });
  });

  test("today's orders: the whole night, not the morning after", () {
    final orders = [
      o('evening', DateTime(2026, 11, 12, 19, 10)),
      o('late', DateTime(2026, 11, 13, 1, 45)),
      o('prevNight', DateTime(2026, 11, 12, 1, 0)), // belongs to the 11th
      o('nextDay', DateTime(2026, 11, 13, 19, 0)),
    ];
    final at2am = todaysOrders(orders, DateTime(2026, 11, 13, 2)).map((x) => x.id).toSet();
    expect(at2am, {'evening', 'late'});
    final at6am = todaysOrders(orders, DateTime(2026, 11, 13, 6)).map((x) => x.id).toSet();
    expect(at6am, {'nextDay'});
  });

  test('just-placed order without server time counts as today', () {
    expect(todaysOrders([PosOrder('new', {'status': 'pending'})]).single.id, 'new');
  });

  test('daily sales and month use business days', () {
    final orders = [o('a', DateTime(2026, 11, 12, 20)), o('b', DateTime(2026, 11, 13, 1), total: 50), o('c', DateTime(2026, 12, 1, 1), total: 70)];
    final week = SalesStats.dailySales(orders, days: 2, now: DateTime(2026, 11, 13, 1, 30));
    expect(week.last, (DateTime(2026, 11, 12), 150.0));
    final m = MonthSummary.of(orders, DateTime(2026, 11, 30, 23));
    expect(m.sales, 220); // the 1 Dec 1 AM order is still 30 Nov's night
    expect(m.daily[29], 70);
  });
}
