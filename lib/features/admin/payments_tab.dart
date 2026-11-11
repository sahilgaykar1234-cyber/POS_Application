import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';
import 'payment_list.dart';

/// All subscription payments across cafes + who still owes.
class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  String _range = 'all'; // all | month | year
  String _query = '';

  bool _inRange(SubscriptionPayment p, DateTime now) {
    final d = p.paidAt;
    if (d == null) return _range == 'all';
    return switch (_range) {
      'month' => d.year == now.year && d.month == now.month,
      'year' => d.year == now.year,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return StreamBuilder<List<CafeSummary>>(
      stream: AdminService.instance.watchCafes(),
      builder: (context, cafeSnap) {
        final cafes = (cafeSnap.data ?? const <CafeSummary>[]).where((c) => !c.isDeleted).toList();
        final due = cafes.where((c) => c.isOverdue(now) || c.isPaymentPending(now)).toList()
          ..sort((a, b) => (a.expiryDate ?? DateTime(9999)).compareTo(b.expiryDate ?? DateTime(9999)));

        return StreamBuilder<List<SubscriptionPayment>>(
          stream: AdminService.instance.watchPayments(),
          builder: (context, snap) {
            if (snap.hasError) return const EmptyState(icon: Icons.error_outline, title: 'Could not load payments');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            final all = snap.data!;
            final list = all
                .where((p) => _inRange(p, now))
                .where((p) =>
                    _query.isEmpty ||
                    p.cafeName.toLowerCase().contains(_query) ||
                    p.receiptNo.toLowerCase().contains(_query) ||
                    p.referenceId.toLowerCase().contains(_query))
                .toList();
            final total = list.fold<double>(0, (s, p) => s + p.amount);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ResponsiveGrid(children: [
                  StatCard(label: 'Received (${_rangeLabel()})', value: Fmt.money(total), icon: Icons.currency_rupee, color: AppColors.success),
                  StatCard(label: 'Payments', value: '${list.length}', icon: Icons.receipt_long),
                  StatCard(
                    label: 'Cafes with dues',
                    value: '${due.length}',
                    icon: Icons.warning_amber_rounded,
                    color: due.isEmpty ? AppColors.success : AppColors.danger,
                  ),
                ]),
                const SizedBox(height: 16),
                if (due.isNotEmpty)
                  SectionCard(
                    title: 'Pending & overdue',
                    icon: Icons.hourglass_bottom,
                    child: Column(
                      children: [
                        for (final c in due)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${c.isOverdue(now) ? 'Overdue — expired' : 'Pending — expires'} ${Fmt.date(c.expiryDate)} · ${Fmt.money(c.amount)}',
                              style: TextStyle(color: c.isOverdue(now) ? AppColors.danger : AppColors.accent, fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CafeDetailScreen(cafeId: c.id))),
                          ),
                      ],
                    ),
                  ),
                SectionCard(
                  title: 'Payment history',
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final r in const [('all', 'All time'), ('year', 'This year'), ('month', 'This month')])
                            ChoiceChip(label: Text(r.$2), selected: _range == r.$1, onSelected: (_) => setState(() => _range = r.$1)),
                          SizedBox(
                            width: 260,
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Cafe, receipt or reference',
                                prefixIcon: Icon(Icons.search),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('To record a payment, open the cafe → Subscription tab.',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                      PaymentList(payments: list),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _rangeLabel() => switch (_range) {
        'month' => 'this month',
        'year' => 'this year',
        _ => 'all time',
      };
}
