import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// An item that is not on the menu (e.g. a cold drink or cigarettes the
/// manager fetched for the customer), added to an order with its own price.
class CustomItem {
  const CustomItem(this.name, this.price, this.qty);
  final String name;
  final double price;
  final int qty;

  /// Stored order-item shape. Not sent to the kitchen (isDone: true).
  Map<String, dynamic> toLine() =>
      {'name': name, 'price': price, 'size': 'Standard', 'qty': qty, 'isDone': true, 'custom': true};

  /// Validates the dialog input; returns null when it is not a usable item.
  static CustomItem? parse(String name, String price, String qty) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final p = double.tryParse(price.trim());
    final q = int.tryParse(qty.trim());
    if (n.isEmpty || p == null || p <= 0 || p > 100000 || q == null || q < 1 || q > 999) return null;
    return CustomItem(n, (p * 100).roundToDouble() / 100, q);
  }
}

/// Asks for name, price and quantity of an extra (off-menu) item.
Future<CustomItem?> showCustomItemDialog(BuildContext context) {
  final name = TextEditingController();
  final price = TextEditingController();
  final qty = TextEditingController(text: '1');
  return showDialog<CustomItem>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final item = CustomItem.parse(name.text, price.text, qty.text);
      void submit() {
        if (item != null) Navigator.pop(ctx, item);
      }

      return AlertDialog(
        title: const Text('Add extra item'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('For things not on the menu, e.g. a cold drink or water bottle bought for the customer.',
                    style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 13)),
                const SizedBox(height: Space.lg),
                TextField(
                  key: const Key('custom-name'),
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Item name', hintText: 'e.g. Coke 750 ml'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.md),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const Key('custom-price'),
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(labelText: 'Price (each)', prefixText: '₹ '),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const Key('custom-qty'),
                      controller: qty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Qty'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: item == null ? null : submit,
            child: Text(item == null ? 'Add' : 'Add  ₹${_fmt(item.price * item.qty)}'),
          ),
        ],
      );
    }),
  );
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
