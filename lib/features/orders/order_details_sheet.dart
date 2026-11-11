import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';
import '../../receipt_screen.dart';
import '../menu/menu_models.dart' show formatPrice;
import '../pos/pos_screen.dart';
import '../pos/print_helper.dart';
import '../settings/business_settings.dart';
import 'custom_item_dialog.dart';
import 'order_model.dart';
import 'order_service.dart';
import 'settle_bill_sheet.dart';

/// Everything you can do with one running order (table tap).
Future<void> showOrderDetailsSheet(
  BuildContext context,
  PosOrder order,
  BusinessSettings settings, {
  required bool canDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetCtx) => _OrderDetails(order: order, settings: settings, canDelete: canDelete, parent: context),
  );
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({required this.order, required this.settings, required this.canDelete, required this.parent});
  final PosOrder order;
  final BusinessSettings settings;
  final bool canDelete;
  final BuildContext parent;

  Future<void> _run(BuildContext sheetCtx, Future<void> Function() fn, String ok) async {
    Navigator.pop(sheetCtx);
    try {
      await fn();
      if (parent.mounted) showSuccess(parent, ok);
    } catch (_) {
      if (parent.mounted) showError(parent, 'Could not update the order. Please check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = order;
    final minutes = o.createdAt == null ? null : DateTime.now().difference(o.createdAt!).inMinutes;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.displayName, style: context.text.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        o.billNo,
                        o.orderType,
                        if (o.customerPhone.isNotEmpty) o.customerPhone,
                        if (minutes != null) '$minutes min ago',
                      ].join(' · '),
                      style: TextStyle(color: p.inkSubtle, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(o.statusLabel),
                  const SizedBox(height: 4),
                  StatusChip(o.isPaid ? 'Paid · ${o.paymentLabel}' : 'Payment due',
                      color: o.isPaid ? p.success : p.warning, tint: o.isPaid ? p.successTint : p.warningTint),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.cardR),
            child: Column(
              children: [
                for (final it in o.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 30, child: Text('${it['qty'] ?? 1}×', style: TextStyle(fontWeight: FontWeight.w700, color: p.inkSubtle))),
                        Expanded(
                          child: Text('${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' (${it['size']})' : ''}'),
                        ),
                        Text(Fmt.money(((it['price'] ?? 0) as num) * ((it['qty'] ?? 1) as num)),
                            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ),
                if (o.specialRequest.isNotEmpty) ...[
                  const Divider(height: Space.lg),
                  Row(children: [
                    Icon(Icons.sticky_note_2_outlined, size: 16, color: p.warning),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(o.specialRequest, style: TextStyle(color: p.warning, fontWeight: FontWeight.w600))),
                  ]),
                ],
                const Divider(height: Space.lg),
                Row(
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    MoneyText(o.totalPrice, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),

          // Kitchen status
          if (o.status == 'pending')
            _ActionButton(
              icon: Icons.local_fire_department_outlined,
              label: 'Start cooking',
              onTap: () => _run(context, () => OrderService.instance.setStatus(o.id, 'preparing'), 'Marked as preparing'),
            ),
          if (o.status == 'preparing')
            _ActionButton(
              icon: Icons.room_service_outlined,
              label: 'Food ready',
              onTap: () => _run(context, () => OrderService.instance.setStatus(o.id, 'ready'), 'Marked as ready'),
            ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                showSettleBillSheet(parent, o, settings);
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(o.isPaid ? 'Bill & free table' : 'Settle bill', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(parent, MaterialPageRoute(builder: (_) => PosScreen(editing: o, standalone: true)));
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add items'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => printBill(context, order: o.data, settings: settings.receiptSettings, orderId: o.id),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            key: const Key('details-add-extra'),
            onPressed: () async {
              final item = await showCustomItemDialog(context);
              if (item == null || !context.mounted) return;
              await _run(context, () => OrderService.instance.addCustomItem(o, item.toLine()),
                  '${item.name} added · ₹${formatPrice(item.price * item.qty)}');
            },
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
            label: const Text('Extra item (not on menu)'),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Free ${o.displayName}?',
                      message: 'The bill will be closed and the table marked free${o.isPaid ? '' : ' without recording a payment'}.',
                      confirmLabel: 'Free table',
                    );
                    if (!ok || !context.mounted) return;
                    Navigator.pop(context);
                    try {
                      final data = await OrderService.instance.complete(o.id, assignBillNumber: settings.autoGenBillNumber);
                      if (!parent.mounted) return;
                      Navigator.push(
                        parent,
                        MaterialPageRoute(
                          builder: (_) => PaymentCompleteReceiptScreen(orderData: data, orderId: o.id, businessSettings: settings.receiptSettings),
                        ),
                      );
                    } catch (_) {
                      if (parent.mounted) showError(parent, 'Could not close the bill.');
                    }
                  },
                  child: const Text('Free table only'),
                ),
              ),
              if (canDelete)
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: () async {
                      final ok = await showDangerConfirmDialog(
                        context,
                        title: 'Delete this order?',
                        message: '${o.displayName} · ${Fmt.money(o.totalPrice)}\nThis cannot be undone.',
                        confirmLabel: 'Delete',
                      );
                      if (!ok || !context.mounted) return;
                      await _run(context, () => OrderService.instance.delete(o.id), 'Order deleted');
                    },
                    child: const Text('Delete order'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: context.palette.info, side: BorderSide(color: context.palette.info)),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}
