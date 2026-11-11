import 'package:flutter/foundation.dart';

import '../menu/menu_models.dart';
import '../orders/bill.dart';
import '../orders/order_model.dart';

/// The order being built at the POS. Lines use the stored order item shape:
/// {name, price, size, qty, isDone}.
class PosCart extends ChangeNotifier {
  final List<Map<String, dynamic>> lines = [];
  String orderType = 'Dine-In';
  PosOrder? editing;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (n, l) => n + ((l['qty'] ?? 1) as num).toInt());

  Bill bill({required bool gstEnabled, required double gstPercent}) =>
      Bill.compute(items: lines, gstEnabled: gstEnabled, gstPercent: gstPercent);

  /// Total quantity of a menu item across all its sizes/add-ons.
  int qtyOfItem(String itemName) => lines
      .where((l) => l['name'] == itemName || l['name'].toString().startsWith('$itemName + '))
      .fold(0, (n, l) => n + ((l['qty'] ?? 1) as num).toInt());

  /// Same merging rule as before: same name + same size → qty + 1.
  void add(CartLine line) {
    final i = lines.indexWhere((l) => l['custom'] != true && l['name'] == line.name && l['size'] == line.size);
    if (i != -1) {
      lines[i]['qty'] = ((lines[i]['qty'] ?? 1) as num).toInt() + 1;
    } else {
      lines.add({'name': line.name, 'price': line.unitPrice, 'size': line.size, 'qty': 1, 'isDone': false});
    }
    notifyListeners();
  }

  /// Adds an off-menu item with its own price (merges same name + price).
  void addCustom(Map<String, dynamic> line) {
    final i = lines.indexWhere((l) => l['custom'] == true && l['name'] == line['name'] && l['price'] == line['price']);
    if (i != -1) {
      lines[i]['qty'] = ((lines[i]['qty'] ?? 1) as num).toInt() + ((line['qty'] ?? 1) as num).toInt();
    } else {
      lines.add({...line});
    }
    notifyListeners();
  }

  void setQty(int index, int qty) {
    if (index < 0 || index >= lines.length) return;
    if (qty <= 0) {
      lines.removeAt(index);
    } else {
      lines[index]['qty'] = qty;
    }
    notifyListeners();
  }

  /// For single-size items shown with a stepper on phones.
  int indexOfSimple(MenuItem item) =>
      item.variants.isEmpty ? -1 : lines.indexWhere((l) => l['name'] == item.name && l['size'] == item.variants.first.label);

  /// Re-adds a returning customer's last items at their old prices.
  void addAll(Iterable<Map<String, dynamic>> items) {
    for (final it in items) {
      lines.add({
        'name': it['name'],
        'price': it['price'],
        'size': it['size'] ?? 'Standard',
        'qty': it['qty'] ?? 1,
        'isDone': false,
      });
    }
    notifyListeners();
  }

  void loadFrom(PosOrder order) {
    editing = order;
    lines
      ..clear()
      ..addAll(order.items.map((e) => {...e, 'isDone': e['isDone'] ?? false}));
    orderType = order.orderType;
    notifyListeners();
  }

  void setOrderType(String t) {
    orderType = t;
    notifyListeners();
  }

  /// Ask listeners (e.g. the phone cart sheet) to rebuild.
  void touch() => notifyListeners();

  void clear({String? orderType}) {
    lines.clear();
    editing = null;
    if (orderType != null) this.orderType = orderType;
    notifyListeners();
  }
}
