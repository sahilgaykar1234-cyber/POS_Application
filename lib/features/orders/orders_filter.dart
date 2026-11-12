import '../../core/utils/business_day.dart';
import 'order_model.dart';

enum OrderStatusFilter {
  all('All statuses'),
  running('Running'),
  completed('Completed'),
  cancelled('Cancelled');

  const OrderStatusFilter(this.label);
  final String label;
}

enum PaymentFilter {
  all('All payments'),
  paid('Paid'),
  unpaid('Unpaid'),
  cash('Cash'),
  upi('UPI'),
  card('Card');

  const PaymentFilter(this.label);
  final String label;
}

enum DatePreset {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  thisMonth('This month'),
  custom('Custom');

  const DatePreset(this.label);
  final String label;

  /// [from, to) of business days for this preset around [now] (custom: null).
  (DateTime, DateTime)? range(DateTime now) {
    final today = BusinessDay.dateOf(now);
    DateTime back(int days) => DateTime(today.year, today.month, today.day - days);
    return switch (this) {
      DatePreset.today => BusinessDay.range(today, today),
      DatePreset.yesterday => BusinessDay.range(back(1), back(1)),
      DatePreset.last7 => BusinessDay.range(back(6), today),
      DatePreset.thisMonth => BusinessDay.range(DateTime(today.year, today.month), today),
      DatePreset.custom => null,
    };
  }
}

/// Search + filters for the Orders screen (pure, unit-tested). Newest first.
List<PosOrder> filterOrders(
  Iterable<PosOrder> orders, {
  String search = '',
  OrderStatusFilter status = OrderStatusFilter.all,
  PaymentFilter payment = PaymentFilter.all,
}) {
  final q = search.trim().toLowerCase().replaceAll('#', '');
  bool matches(PosOrder o) {
    if (q.isEmpty) return true;
    return o.billNo.toLowerCase().replaceAll('#', '').contains(q) ||
        o.id.toLowerCase().startsWith(q) ||
        o.customerName.toLowerCase().contains(q) ||
        o.customerPhone.contains(q) ||
        o.tableNo.toLowerCase() == q ||
        'table ${o.tableNo}'.toLowerCase() == q ||
        (o.tokenNo != null && ('${o.tokenNo}' == q || 'token ${o.tokenNo}' == q));
  }

  bool statusOk(PosOrder o) => switch (status) {
        OrderStatusFilter.all => true,
        OrderStatusFilter.running => o.isActive,
        OrderStatusFilter.completed => o.isCompleted,
        OrderStatusFilter.cancelled => o.isCancelled,
      };

  bool paymentOk(PosOrder o) => switch (payment) {
        PaymentFilter.all => true,
        PaymentFilter.paid => o.isPaid,
        PaymentFilter.unpaid => !o.isPaid,
        PaymentFilter.cash => o.paymentStatus == 'paid_cash',
        PaymentFilter.upi => o.paymentStatus == 'paid_upi',
        PaymentFilter.card => o.paymentStatus == 'paid_card',
      };

  return orders.where((o) => matches(o) && statusOk(o) && paymentOk(o)).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
}

/// One page of [list]: items [page*size, page*size+size).
List<T> pageOf<T>(List<T> list, int page, int size) {
  final start = page * size;
  if (start >= list.length) return const [];
  return list.sublist(start, (start + size).clamp(0, list.length));
}
