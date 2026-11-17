import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/widgets/ui.dart';
import 'order_model.dart';
import 'order_service.dart';
import 'package:pos_app/core/i18n/tr.dart';

const kVoidReasons = ['Customer cancelled', 'Wrong order', 'Duplicate bill', 'Test bill'];

/// Asks why, then cancels (voids) the bill. Bills are never deleted: the
/// bill keeps its number and shows as "Cancelled". Returns true if voided.
Future<bool> showVoidBillDialog(BuildContext context, PosOrder order) async {
  final other = TextEditingController();
  String? picked;
  var saving = false;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final p = ctx.palette;
      final reason = (picked == 'Other' ? other.text : picked ?? '').trim();
      return AlertDialog(
        title: Text(tr('Cancel bill {0}?', [order.billNo])),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              '${order.displayName} · ${Fmt.money(order.totalPrice)}${order.isPaid ? ' · already paid' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.xs),
            Text(tr('The bill keeps its number and shows as Cancelled; it is removed from sales. The reason is saved.'),
                style: TextStyle(color: p.inkSubtle, fontSize: 13)),
            const SizedBox(height: Space.md),
            Text(tr('Reason *'), style: TextStyle(color: p.inkSubtle, fontSize: 13)),
            const SizedBox(height: Space.xs),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
              for (final r in [...kVoidReasons, 'Other'])
                ChoiceChip(key: Key('void-$r'), label: Text(tr(r)), selected: picked == r, onSelected: (_) => setState(() => picked = r)),
            ]),
            if (picked == 'Other') ...[
              const SizedBox(height: Space.sm),
              TextField(
                key: const Key('void-other'),
                controller: other,
                autofocus: true,
                maxLength: 120,
                decoration: InputDecoration(labelText: tr('Write the reason')),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(tr('Keep bill'))),
          FilledButton(
            key: const Key('void-confirm'),
            style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: ctx.onStatusFill),
            onPressed: saving || reason.isEmpty
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await OrderService.instance.voidOrder(order, reason: reason);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setState(() => saving = false);
                      if (ctx.mounted) showError(ctx, friendlyError(e, tr('cancel the bill')));
                    }
                  },
            child: Text(saving ? tr('Cancelling…') : tr('Cancel bill')),
          ),
        ],
      );
    }),
  );
  if (done == true && context.mounted) showSuccess(context, tr('Bill {0} cancelled', [order.billNo]));
  return done == true;
}
