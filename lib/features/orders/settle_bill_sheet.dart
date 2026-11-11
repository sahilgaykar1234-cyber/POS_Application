import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../receipt_screen.dart';
import '../menu/menu_models.dart' show formatPrice;
import '../pos/print_helper.dart';
import '../settings/business_settings.dart';
import 'bill.dart';
import 'order_model.dart';
import 'order_service.dart';

/// Billing & checkout: discount, payment method, cash received / change,
/// then "Mark paid" or "Paid & free table" (shows the receipt).
Future<void> showSettleBillSheet(BuildContext context, PosOrder order, BusinessSettings settings) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _SettleSheet(order: order, settings: settings, parentContext: context),
  );
}

class _SettleSheet extends StatefulWidget {
  const _SettleSheet({required this.order, required this.settings, required this.parentContext});
  final PosOrder order;
  final BusinessSettings settings;
  final BuildContext parentContext;

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  late DiscountType _dType = Bill.parseType(widget.order.data['discountType']);
  late final _dValue = TextEditingController(
    text: _dType == DiscountType.none ? '' : formatPrice(((widget.order.data['discountValue'] ?? 0) as num).toDouble()),
  );
  late PaymentMethod _method = methodFromStatus(widget.order.paymentStatus) ?? PaymentMethod.cash;
  final _cash = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _dValue.dispose();
    _cash.dispose();
    super.dispose();
  }

  double get _gstPct => ((widget.order.data['gstPercentage'] ?? 5) as num).toDouble();

  Bill get _bill => Bill.compute(
        items: widget.order.items,
        gstEnabled: widget.order.hasGst,
        gstPercent: _gstPct,
        discountType: _dType,
        discountValue: double.tryParse(_dValue.text.trim()) ?? 0,
      );

  double? get _cashReceived => double.tryParse(_cash.text.trim());

  Map<String, dynamic> _draftWithDiscount() {
    final b = _bill;
    return {
      ...widget.order.data,
      'subtotal': b.subtotal,
      'totalPrice': b.total,
      'discountGiven': b.discount,
      'paymentStatus': _method.status,
    };
  }

  Future<void> _settle({required bool complete}) async {
    final b = _bill;
    if (_method == PaymentMethod.cash && _cashReceived != null && _cashReceived! < b.total) {
      return showError(context, 'Cash received is less than the total.');
    }
    setState(() => _busy = true);
    try {
      final data = await OrderService.instance.settle(
        order: widget.order,
        method: _method,
        discountType: (double.tryParse(_dValue.text.trim()) ?? 0) > 0 ? _dType : DiscountType.none,
        discountValue: double.tryParse(_dValue.text.trim()) ?? 0,
        cashReceived: _cashReceived,
        complete: complete,
        assignBillNumber: widget.settings.autoGenBillNumber,
      );
      if (!mounted) return;
      final parent = widget.parentContext;
      Navigator.pop(context);
      if (complete && parent.mounted) {
        Navigator.push(
          parent,
          MaterialPageRoute(
            builder: (_) => PaymentCompleteReceiptScreen(
              orderData: data,
              orderId: widget.order.id,
              businessSettings: widget.settings.receiptSettings,
            ),
          ),
        );
      } else if (parent.mounted) {
        showSuccess(parent, 'Payment saved · ${_method.label}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, 'Could not save the payment. Please check your connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = _bill;
    final change = (_cashReceived ?? 0) - b.total;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Settle bill', style: context.text.headlineSmall)),
                Text(widget.order.billNo, style: TextStyle(color: p.inkSubtle, fontWeight: FontWeight.w600)),
              ],
            ),
            Text(widget.order.displayName, style: TextStyle(color: p.inkSubtle)),
            const SizedBox(height: Space.lg),

            // Items summary
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.cardR),
              child: Column(
                children: [
                  for (final it in widget.order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(width: 28, child: Text('${it['qty'] ?? 1}×', style: TextStyle(color: p.inkSubtle, fontWeight: FontWeight.w600))),
                          Expanded(
                            child: Text(
                              '${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' (${it['size']})' : ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            Fmt.money(((it['price'] ?? 0) as num) * ((it['qty'] ?? 1) as num)),
                            style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),

            // Discount
            Text('Discount', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                SegmentedButton<DiscountType>(
                  segments: const [
                    ButtonSegment(value: DiscountType.none, label: Text('None')),
                    ButtonSegment(value: DiscountType.percent, label: Text('%')),
                    ButtonSegment(value: DiscountType.amount, label: Text('₹')),
                  ],
                  selected: {_dType},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _dType = s.first;
                    if (_dType == DiscountType.none) _dValue.clear();
                  }),
                ),
                const SizedBox(width: Space.md),
                if (_dType != DiscountType.none)
                  Expanded(
                    child: TextField(
                      controller: _dValue,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        hintText: _dType == DiscountType.percent ? 'e.g. 10' : 'e.g. 50',
                        suffixText: _dType == DiscountType.percent ? '%' : '₹',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ],
            ),
            if (_dType == DiscountType.percent) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                children: [
                  for (final v in [5, 10, 15, 20])
                    ActionChip(label: Text('$v%'), onPressed: () => setState(() => _dValue.text = '$v')),
                ],
              ),
            ],
            const SizedBox(height: Space.lg),

            // Payment method
            Text('Payment method', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (final m in PaymentMethod.values) ...[
                  Expanded(
                    child: _MethodButton(
                      method: m,
                      selected: _method == m,
                      onTap: () => setState(() => _method = m),
                    ),
                  ),
                  if (m != PaymentMethod.values.last) const SizedBox(width: Space.sm),
                ],
              ],
            ),
            if (_method == PaymentMethod.cash) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cash,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(labelText: 'Cash received', prefixText: '₹ '),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      decoration: BoxDecoration(
                        color: _cashReceived == null ? p.surfaceAlt : (change >= 0 ? p.successTint : p.dangerTint),
                        borderRadius: Radii.controlR,
                      ),
                      child: Row(
                        children: [
                          Text('Change', style: TextStyle(color: p.inkSubtle, fontSize: 13)),
                          const Spacer(),
                          Text(
                            _cashReceived == null ? '—' : (change >= 0 ? Fmt.money(change) : 'Short ${Fmt.money(-change)}'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: _cashReceived == null ? p.inkSubtle : (change >= 0 ? p.success : p.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                children: [
                  for (final note in _quickCash(b.total))
                    ActionChip(label: Text('₹$note'), onPressed: () => setState(() => _cash.text = '$note')),
                ],
              ),
            ],
            const SizedBox(height: Space.lg),

            // Totals
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: Radii.cardR),
              child: Column(
                children: [
                  _row('Subtotal', Fmt.money(b.subtotal)),
                  if (b.discount > 0) _row('Discount', '− ₹${b.discount.toStringAsFixed(2)}', color: p.primaryHover),
                  if (b.gstEnabled) _row('GST ${formatPrice(b.gstPercent)}%', '₹${b.gst.toStringAsFixed(2)}'),
                  const Divider(height: Space.lg),
                  Row(
                    children: [
                      Text('Grand total', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      MoneyText(b.total, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => printBill(context, order: _draftWithDiscount(), settings: widget.settings.receiptSettings, orderId: widget.order.id),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _settle(complete: false),
                    child: const Text('Mark paid'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: context.onStatusFill),
                onPressed: _busy ? null : () => _settle(complete: true),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: Text(widget.order.isTakeaway && widget.order.tableNo.isEmpty ? 'Paid & hand over' : 'Paid & free table',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String l, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(l, style: TextStyle(color: color ?? context.palette.inkMuted)),
            const Spacer(),
            Text(v, style: TextStyle(color: color ?? context.palette.inkMuted, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      );

  /// Exact amount and the next round notes above it.
  static List<int> _quickCash(double total) {
    final exact = total.ceil();
    final out = <int>{exact};
    for (final step in [50, 100, 500, 2000]) {
      final v = ((exact + step - 1) ~/ step) * step;
      if (v >= exact) out.add(v);
    }
    return out.toList()..sort();
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.method, required this.selected, required this.onTap});
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final icon = switch (method) {
      PaymentMethod.cash => Icons.payments_outlined,
      PaymentMethod.upi => Icons.qr_code_2_rounded,
      PaymentMethod.card => Icons.credit_card_rounded,
    };
    return Material(
      color: selected ? p.primaryTint : p.surface,
      shape: RoundedRectangleBorder(borderRadius: Radii.controlR, side: BorderSide(color: selected ? p.primary : p.borderStrong, width: selected ? 2 : 1)),
      child: InkWell(
        borderRadius: Radii.controlR,
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? p.primary : p.inkSubtle),
              Text(method.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? p.primaryHover : p.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
