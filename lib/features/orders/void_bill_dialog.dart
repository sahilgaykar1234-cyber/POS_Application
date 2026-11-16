import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/widgets/ui.dart';
import 'order_model.dart';
import 'order_service.dart';

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
        title: Text('Cancel bill ${order.billNo}?'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              '${order.displayName} · ${Fmt.money(order.totalPrice)}${order.isPaid ? ' · already paid' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.xs),
            Text('The bill keeps its number and shows as Cancelled; it is removed from sales. The reason is saved.',
                style: TextStyle(color: p.inkSubtle, fontSize: 13)),
            const SizedBox(height: Space.md),
            Text('Reason *', style: TextStyle(color: p.inkSubtle, fontSize: 13)),
            const SizedBox(height: Space.xs),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
              for (final r in [...kVoidReasons, 'Other'])
                ChoiceChip(key: Key('void-$r'), label: Text(r), selected: picked == r, onSelected: (_) => setState(() => picked = r)),
            ]),
            if (picked == 'Other') ...[
              const SizedBox(height: Space.sm),
              TextField(
                key: const Key('void-other'),
                controller: other,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Write the reason'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Keep bill')),
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
                      if (ctx.mounted) showError(ctx, friendlyError(e, 'cancel the bill'));
                    }
                  },
            child: Text(saving ? 'Cancelling…' : 'Cancel bill'),
          ),
        ],
      );
    }),
  );
  if (done == true && context.mounted) showSuccess(context, 'Bill ${order.billNo} cancelled');
  return done == true;
}
