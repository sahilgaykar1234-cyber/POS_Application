import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_dialogs.dart';
import 'admin_service.dart';

/// Pure filter for subscription payments (unit-tested). Newest first.
List<SubscriptionPayment> filterPayments(
  List<SubscriptionPayment> list, {
  DateTimeRange? range,
  String? cafeId,
  String? plan,
  String? method,
  String status = 'all',
}) =>
    list.where((x) {
      if (cafeId != null && x.cafeId != cafeId) return false;
      if (plan != null && x.planName != plan) return false;
      if (method != null && x.method != method) return false;
      if (status != 'all' && x.status != status) return false;
      if (range != null) {
        final d = x.paidAt;
        if (d == null || d.isBefore(range.start) || !d.isBefore(DateTime(range.end.year, range.end.month, range.end.day + 1))) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b.paidAt ?? DateTime(0)).compareTo(a.paidAt ?? DateTime(0)));

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  DateTimeRange? _range;
  String? _cafe;
  String? _plan;
  String? _method;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.cafes.isEmpty) return const LoadingState();
        final p = context.palette;
        final list = filterPayments(d.payments, range: _range, cafeId: _cafe, plan: _plan, method: _method);
        final total = list.where((x) => x.status != 'refunded').fold<double>(0, (t, x) => t + x.amount);
        final plans = {for (final x in d.payments) if (x.planName.isNotEmpty) x.planName}.toList()..sort();
        return PageBody(children: [
          PageHeader(
            title: 'Payments',
            subtitle: 'Subscription money recorded by you (not customers\' bills) · ${list.length} shown · ${Fmt.money(total)}',
            actions: [FilledButton.icon(key: const Key('record-payment'), onPressed: () => showRecordPayment(context, d.cafes), icon: const Icon(Icons.add, size: 18), label: const Text('Record payment'))],
          ),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 700;
            final w = narrow ? (c.maxWidth - Space.sm) / 2 : 180.0;
            return Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              SizedBox(
                width: narrow ? double.infinity : 240,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1), initialDateRange: _range);
                    if (r != null) setState(() => _range = r);
                  },
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(_range == null ? 'Any date' : '${Fmt.date(_range!.start)} – ${Fmt.date(_range!.end)}'),
                ),
              ),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<String?>(
                  initialValue: _cafe,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [const DropdownMenuItem(value: null, child: Text('All cafes')), for (final x in d.cafes) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _cafe = v),
                ),
              ),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<String?>(
                  initialValue: _plan,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [const DropdownMenuItem(value: null, child: Text('All plans')), for (final x in plans) DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _plan = v),
                ),
              ),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<String?>(
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [const DropdownMenuItem(value: null, child: Text('All methods')), for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (v) => setState(() => _method = v),
                ),
              ),
              if (_range != null || _cafe != null || _plan != null || _method != null)
                TextButton(onPressed: () => setState(() => _range = _cafe = _plan = _method = null), child: const Text('Clear filters')),
            ]);
          }),
          const SizedBox(height: Space.lg),
          SurfaceCard(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.payments_outlined,
                    title: d.payments.isEmpty ? 'No payments recorded yet' : 'No payment matches',
                    message: d.payments.isEmpty ? 'When a cafe pays you for its subscription, record it here.' : null,
                  )
                : Column(children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${list[i].cafeName.isEmpty ? d.cafeName(list[i].cafeId) : list[i].cafeName} · ${list[i].receiptNo}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                [Fmt.date(list[i].paidAt), list[i].method, if (list[i].planName.isNotEmpty) list[i].planName, if (list[i].referenceId.isNotEmpty) 'Ref ${list[i].referenceId}'].join(' · '),
                                style: TextStyle(color: p.inkSubtle, fontSize: 12.5),
                              ),
                            ]),
                          ),
                          StatusChip(list[i].status == 'refunded' ? 'Refunded' : 'Received', color: list[i].status == 'refunded' ? p.danger : p.success, tint: list[i].status == 'refunded' ? p.dangerTint : p.successTint),
                          const SizedBox(width: Space.md),
                          MoneyText(list[i].amount, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ],
                  ]),
          ),
        ]);
      },
    );
  }
}
