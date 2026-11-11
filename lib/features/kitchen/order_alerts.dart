import '../orders/order_model.dart';

enum OrderAlertKind { newOrder, itemsAdded }

class OrderAlert {
  const OrderAlert(this.kind, this.order);
  final OrderAlertKind kind;
  final PosOrder order;

  String get title => kind == OrderAlertKind.newOrder ? 'New order' : 'Items added';

  /// "Table 4" / "Takeaway · Token #12" / customer name.
  String get where {
    final o = order;
    if (o.tableNo.trim().isNotEmpty) return 'Table ${o.tableNo.trim()}';
    if (o.isTakeaway) return o.tokenNo != null ? 'Takeaway · Token #${o.tokenNo}' : 'Takeaway';
    return o.displayName;
  }

  /// Items the kitchen has to make (extra off-menu items are not cooked).
  List<Map<String, dynamic>> get kitchenItems {
    final all = order.items.where((it) => it['custom'] != true).toList();
    if (kind == OrderAlertKind.itemsAdded) {
      final fresh = all.where((it) => it['isDone'] != true).toList();
      if (fresh.isNotEmpty) return fresh;
    }
    return all;
  }
}

/// Decides when the kitchen should be alerted (pure, unit-tested).
///
/// The first snapshot only records what already exists (no alert for old
/// orders when the screen opens). After that: a new order waiting for the
/// kitchen → "New order"; an order whose kitchen items grow → "Items added".
/// Extra off-menu items (not cooked) never alert.
class OrderAlertDetector {
  final Map<String, int> _seen = {}; // id → kitchen item quantity
  bool _primed = false;

  static int kitchenQty(PosOrder o) => o.items
      .where((it) => it['custom'] != true)
      .fold(0, (n, it) => n + ((it['qty'] ?? 1) as num).toInt());

  List<OrderAlert> update(Iterable<PosOrder> orders) {
    final alerts = <OrderAlert>[];
    final ids = <String>{};
    for (final o in orders) {
      ids.add(o.id);
      final qty = kitchenQty(o);
      final before = _seen[o.id];
      if (_primed && o.isActive && o.status == 'pending' && qty > 0) {
        if (before == null) {
          alerts.add(OrderAlert(OrderAlertKind.newOrder, o));
        } else if (qty > before) {
          alerts.add(OrderAlert(OrderAlertKind.itemsAdded, o));
        }
      }
      _seen[o.id] = qty;
    }
    _seen.removeWhere((id, _) => !ids.contains(id));
    _primed = true;
    return alerts;
  }
}
