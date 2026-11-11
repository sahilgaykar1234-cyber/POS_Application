import '../orders/bill.dart';
import '../orders/order_model.dart';

/// Pure sales maths for the dashboard (unit-tested).
///
/// "Sales" = bills that are PAID (any method), the same rule the original
/// dashboard used for "Today's Sales" (it counted paid_cash + paid_upi).
class SalesStats {
  SalesStats._({
    required this.sales,
    required this.orders,
    required this.running,
    required this.completed,
    required this.cancelled,
    required this.unpaid,
    required this.byMethod,
    required this.byHour,
    required this.topItems,
  });

  final double sales;
  final int orders;
  final int running;
  final int completed;
  final int cancelled;
  final int unpaid;
  final Map<PaymentMethod, double> byMethod;

  /// 24 buckets (hour of order creation) of paid sales.
  final List<double> byHour;

  /// (item name, qty) sorted by qty, top 5.
  final List<(String, int)> topItems;

  double get averageBill {
    final paidCount = orders - unpaid - cancelled;
    return paidCount > 0 ? sales / paidCount : 0;
  }

  static SalesStats of(List<PosOrder> orders) {
    double sales = 0;
    var running = 0, completed = 0, cancelled = 0, unpaid = 0;
    final byMethod = {for (final m in PaymentMethod.values) m: 0.0};
    final byHour = List<double>.filled(24, 0);
    final qty = <String, int>{};

    for (final o in orders) {
      if (o.isCancelled) {
        cancelled++;
        continue;
      }
      if (o.isCompleted) {
        completed++;
      } else {
        running++;
      }
      if (o.isPaid) {
        sales += o.totalPrice;
        final m = methodFromStatus(o.paymentStatus);
        if (m != null) byMethod[m] = byMethod[m]! + o.totalPrice;
        final h = o.createdAt?.hour;
        if (h != null) byHour[h] += o.totalPrice;
      } else {
        unpaid++;
      }
      for (final it in o.items) {
        final name = it['name'].toString().split(' + ').first;
        qty[name] = (qty[name] ?? 0) + ((it['qty'] ?? 1) as num).toInt();
      }
    }
    final top = qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SalesStats._(
      sales: sales,
      orders: orders.length,
      running: running,
      completed: completed,
      cancelled: cancelled,
      unpaid: unpaid,
      byMethod: byMethod,
      byHour: byHour,
      topItems: [for (final e in top.take(5)) (e.key, e.value)],
    );
  }

  /// Orders whose createdAt is within [from, to).
  static List<PosOrder> between(Iterable<PosOrder> all, DateTime from, DateTime to) =>
      all.where((o) => o.createdAt != null && !o.createdAt!.isBefore(from) && o.createdAt!.isBefore(to)).toList();

  /// Paid sales per day for the last [days] days (oldest first), ending today.
  static List<(DateTime, double)> dailySales(Iterable<PosOrder> all, {int days = 7, DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = today.subtract(Duration(days: i));
          final s = between(all, d, d.add(const Duration(days: 1)))
              .where((o) => o.isPaid && !o.isCancelled)
              .fold<double>(0, (t, o) => t + o.totalPrice);
          return (d, s);
        }(),
    ];
  }
}

/// "This month" numbers for the dashboard, compared with the same days of
/// the previous month (1st → today's date), so a half-finished month is not
/// compared with a full one. Only real order data; nothing estimated.
class MonthSummary {
  MonthSummary._({
    required this.sales,
    required this.orders,
    required this.paidBills,
    required this.prevSales,
    required this.prevOrders,
    required this.daily,
    required this.bestDay,
    required this.bestDaySales,
  });

  final double sales;
  final int orders; // not cancelled
  final int paidBills;
  final double prevSales;
  final int prevOrders;

  /// Paid sales per day of this month, day 1 → today.
  final List<double> daily;
  final DateTime? bestDay;
  final double bestDaySales;

  double get averageBill => paidBills > 0 ? sales / paidBills : 0;
  double get dailyAverage => daily.isEmpty ? 0 : sales / daily.length;

  /// Percent change vs the same days last month; null when there is nothing
  /// to compare with.
  int? get salesChangePct => prevSales > 0 ? ((sales - prevSales) / prevSales * 100).round() : null;
  int? get ordersChangePct => prevOrders > 0 ? ((orders - prevOrders) / prevOrders * 100).round() : null;

  static MonthSummary of(Iterable<PosOrder> all, DateTime now) {
    final monthStart = DateTime(now.year, now.month);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final prevStart = DateTime(now.year, now.month - 1);
    final prevDays = DateTime(now.year, now.month, 0).day;
    final prevEnd = DateTime(now.year, now.month - 1, (now.day < prevDays ? now.day : prevDays) + 1);

    final cur = SalesStats.between(all, monthStart, tomorrow).where((o) => !o.isCancelled).toList();
    final prev = SalesStats.between(all, prevStart, prevEnd).where((o) => !o.isCancelled).toList();

    final daily = List<double>.filled(now.day, 0);
    var sales = 0.0;
    var paid = 0;
    for (final o in cur) {
      if (!o.isPaid) continue;
      sales += o.totalPrice;
      paid++;
      daily[o.createdAt!.day - 1] += o.totalPrice;
    }
    var best = -1;
    for (var i = 0; i < daily.length; i++) {
      if (daily[i] > 0 && (best < 0 || daily[i] > daily[best])) best = i;
    }
    return MonthSummary._(
      sales: sales,
      orders: cur.length,
      paidBills: paid,
      prevSales: prev.where((o) => o.isPaid).fold(0.0, (t, o) => t + o.totalPrice),
      prevOrders: prev.length,
      daily: daily,
      bestDay: best < 0 ? null : DateTime(now.year, now.month, best + 1),
      bestDaySales: best < 0 ? 0 : daily[best],
    );
  }
}
