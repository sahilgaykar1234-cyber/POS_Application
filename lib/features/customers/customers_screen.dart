import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';

class CustomerSummary {
  CustomerSummary({required this.name, required this.phone, required this.lastOrder});
  final String name;
  final String phone;
  final PosOrder lastOrder;
  int orders = 1;
  double spent = 0;
}

/// Same aggregation as the original directory: completed orders only,
/// keyed by phone (else name), newest order first.
List<CustomerSummary> buildCustomers(List<PosOrder> all) {
  final docs = [...all]..sort((a, b) {
      final tA = a.createdAt, tB = b.createdAt;
      if (tA == null && tB == null) return 0;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tB.compareTo(tA);
    });
  final map = <String, CustomerSummary>{};
  for (final o in docs) {
    if (o.status != 'completed') continue;
    var phone = o.customerPhone.trim();
    var name = o.customerName.replaceAll(r'$1', '').replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
    if (RegExp(r'^[a-zA-Z\s]+$').hasMatch(phone) && RegExp(r'^\d{10}').hasMatch(name)) {
      final t = name;
      name = phone;
      phone = t;
    }
    if (name.isEmpty) name = 'Walk-in Guest';
    final key = phone.isNotEmpty ? phone : name.toLowerCase();
    final c = map[key];
    if (c == null) {
      map[key] = CustomerSummary(name: name, phone: phone, lastOrder: o)..spent = o.totalPrice;
    } else {
      c.orders++;
      c.spent += o.totalPrice;
    }
  }
  return map.values.toList();
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.ordersStream});
  final Stream<List<PosOrder>>? ordersStream;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchAll();
  String _q = '';
  String _sort = 'recent';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StreamBuilder<List<PosOrder>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.hasError) return const ErrorState();
        if (!snap.hasData) return const LoadingState();
        var list = buildCustomers(snap.data!);
        final total = list.length;
        final repeat = list.where((c) => c.orders > 1).length;
        final spentAll = list.fold<double>(0, (t, c) => t + c.spent);
        final visits = list.fold<int>(0, (t, c) => t + c.orders);
        if (_q.isNotEmpty) {
          list = list.where((c) => c.name.toLowerCase().contains(_q) || c.phone.contains(_q)).toList();
        }
        if (_sort == 'spent') list.sort((a, b) => b.spent.compareTo(a.spent));
        if (_sort == 'orders') list.sort((a, b) => b.orders.compareTo(a.orders));

        return PageBody(
          children: [
            PageHeader(title: 'Customers', subtitle: '$total customers · $repeat repeat'),
            ResponsiveGrid(minTileWidth: 170, equalHeights: true, fill: true, children: [
              StatCard(label: 'Customers', value: '$total', icon: Icons.groups_outlined, color: p.info, caption: 'With a completed bill'),
              StatCard(
                label: 'Repeat customers',
                value: '$repeat',
                icon: Icons.repeat_rounded,
                color: p.success,
                caption: total == 0 ? 'No customers yet' : '${(repeat / total * 100).round()}% came back',
              ),
              StatCard(label: 'Total spent', value: Fmt.money(spentAll), icon: Icons.account_balance_wallet_outlined, color: p.primary, caption: '$visits visit${visits == 1 ? '' : 's'}'),
              StatCard(
                label: 'Avg per customer',
                value: Fmt.money(total == 0 ? 0 : (spentAll / total).round()),
                icon: Icons.person_outline_rounded,
                color: p.violet,
                caption: 'Lifetime spend',
              ),
            ]),
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SearchField(width: context.isMobile ? double.infinity : 320, hint: 'Search name or phone', onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
                FilterPills<String>(
                  scroll: false,
                  options: const [('recent', 'Recent'), ('spent', 'Top spenders'), ('orders', 'Most visits')],
                  selected: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            if (list.isEmpty)
              EmptyState(icon: Icons.groups_outlined, title: total == 0 ? 'No customers yet' : 'No match', message: total == 0 ? 'Customers appear here after their bill is completed.' : null)
            else
              SurfaceCard(
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      _CustomerTile(c: list[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.c});
  final CustomerSummary c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: p.primaryTint,
          child: Text(c.name.characters.first.toUpperCase(), style: TextStyle(color: p.primary, fontWeight: FontWeight.w800)),
        ),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([if (c.phone.isNotEmpty) c.phone, '${c.orders} visit${c.orders == 1 ? '' : 's'}', 'last ${Fmt.date(c.lastOrder.createdAt)}'].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyText(c.spent, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (c.phone.length >= 10)
              IconButton(
                tooltip: 'Call',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.controlR),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last order · ${Fmt.dateTime(c.lastOrder.createdAt)}${c.lastOrder.tableNo.isNotEmpty ? ' · ${c.lastOrder.tableNo}' : ''}',
                    style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.sm),
                for (final it in c.lastOrder.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${it['qty'] ?? 1}× ${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' (${it['size']})' : ''}'),
                  ),
                const SizedBox(height: Space.sm),
                Text('Total ${Fmt.money(c.lastOrder.totalPrice)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
