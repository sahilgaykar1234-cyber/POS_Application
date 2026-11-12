import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../reports_stub.dart' if (dart.library.html) '../../reports_web.dart';
import '../manager/sales_stats.dart';
import '../orders/bill.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import 'reports_csv.dart';

enum _Period { today, week, month, custom }

/// Sales reports with charts and the original CSV exports.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.ordersStream});
  final Stream<List<PosOrder>>? ordersStream;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchHistory();
  _Period _period = _Period.week;
  late DateTimeRange _range = _rangeFor(_Period.week);

  DateTimeRange _rangeFor(_Period p) {
    final n = DateTime.now();
    final endOfToday = DateTime(n.year, n.month, n.day, 23, 59, 59);
    return switch (p) {
      _Period.today => DateTimeRange(start: DateTime(n.year, n.month, n.day), end: endOfToday),
      _Period.week => () {
          final sow = n.subtract(Duration(days: n.weekday - 1));
          return DateTimeRange(start: DateTime(sow.year, sow.month, sow.day), end: endOfToday);
        }(),
      _Period.month => DateTimeRange(start: DateTime(n.year, n.month, 1), end: endOfToday),
      _Period.custom => _range,
    };
  }

  Future<void> _pickCustom() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(n.year - 3),
      lastDate: n,
      initialDateRange: DateTimeRange(start: _range.start, end: DateTime(_range.end.year, _range.end.month, _range.end.day)),
    );
    if (r == null) return;
    setState(() {
      _period = _Period.custom;
      _range = DateTimeRange(start: r.start, end: DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59));
    });
  }

  void _export(List<PosOrder> all, String kind) {
    final s = _range.start, e = _range.end;
    final (content, name) = switch (kind) {
      'sales' => (salesCsv(all, s, e), 'Sales_Report_${fileDate(s)}_to_${fileDate(e)}.csv'),
      'customers' => (customersCsv(all, s, e), 'Customer_Report_${fileDate(s)}_to_${fileDate(e)}.csv'),
      _ => (itemsCsv(all, s, e), 'Item_Sales_${fileDate(s)}_to_${fileDate(e)}.csv'),
    };
    downloadFileCrossPlatform(content, name);
    showSuccess(context, 'Downloading $name');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PosOrder>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.hasError) return const ErrorState();
        if (!snap.hasData) return const LoadingState(label: 'Building report…');
        return _body(context, snap.data!);
      },
    );
  }

  Widget _body(BuildContext context, List<PosOrder> all) {
    final p = context.palette;
    final from = _range.start;
    final to = _range.end.add(const Duration(seconds: 1));
    final period = SalesStats.between(all, from, to);
    final stats = SalesStats.of(period);
    final billed = period.where((o) => !o.isCancelled).fold<double>(0, (s, o) => s + o.totalPrice);
    final highest = period.fold<double>(0, (m, o) => o.totalPrice > m ? o.totalPrice : m);
    final takeaway = period.where((o) => o.orderType.toLowerCase().contains('takeaway')).length;
    final dineIn = period.length - takeaway;
    final discounts = period.fold<double>(0, (s, o) => s + o.discount);

    // Daily series across the range (max 62 points).
    final days = to.difference(DateTime(from.year, from.month, from.day)).inDays.clamp(1, 62);
    final daily = SalesStats.dailySales(all, days: days, now: _range.end);

    // Items (qty + revenue).
    final itemQty = <String, int>{};
    final itemRev = <String, double>{};
    for (final o in period) {
      for (final it in o.items) {
        final n = it['name'].toString().split(' + ').first;
        final q = ((it['qty'] ?? 1) as num).toInt();
        itemQty[n] = (itemQty[n] ?? 0) + q;
        itemRev[n] = (itemRev[n] ?? 0) + q * ((it['price'] ?? 0) as num).toDouble();
      }
    }
    final topItems = itemQty.keys.toList()..sort((a, b) => itemQty[b]!.compareTo(itemQty[a]!));

    // Customers (same keys as before: phone, else cleaned name).
    String keyOf(PosOrder o) {
      final phone = o.customerPhone.trim();
      final clean = o.customerName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
      return phone.isNotEmpty ? phone : clean.toLowerCase();
    }

    final lifetime = <String, int>{};
    final spend = <String, double>{};
    final names = <String, String>{};
    for (final o in all) {
      final k = keyOf(o);
      lifetime[k] = (lifetime[k] ?? 0) + 1;
      spend[k] = (spend[k] ?? 0) + o.totalPrice;
      final clean = o.customerName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
      names[k] = clean.isEmpty ? 'Guest' : clean;
    }
    final periodKeys = period.map(keyOf).where((k) => k.isNotEmpty).toSet();
    final returning = periodKeys.where((k) => (lifetime[k] ?? 1) > 1).length;
    final topSpender = spend.entries.isEmpty ? null : (spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

    return PageBody(
      children: [
        PageHeader(
          title: 'Reports',
          subtitle: '${Fmt.date(_range.start)} – ${Fmt.date(_range.end)}',
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Export CSV',
              onSelected: (k) => _export(all, k),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sales', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('Sales report'), subtitle: Text('Bill-wise totals, GST, discount'))),
                PopupMenuItem(value: 'customers', child: ListTile(leading: Icon(Icons.groups_outlined), title: Text('Customer report'), subtitle: Text('Visits and spend'))),
                PopupMenuItem(value: 'items', child: ListTile(leading: Icon(Icons.fastfood_outlined), title: Text('Item sales report'), subtitle: Text('Qty and revenue per item'))),
              ],
              child: IgnorePointer(
                child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Export CSV')),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterPills<_Period>(
              scroll: false,
              options: const [(_Period.today, 'Today'), (_Period.week, 'This week'), (_Period.month, 'This month')],
              selected: _period,
              onSelected: (v) => setState(() {
                _period = v;
                _range = _rangeFor(v);
              }),
            ),
            ActionChip(
              avatar: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_period == _Period.custom ? 'Custom range' : 'Pick dates'),
              backgroundColor: _period == _Period.custom ? p.ink : null,
              labelStyle: TextStyle(fontFamily: AppTheme.fontFamily, color: _period == _Period.custom ? p.surface : p.inkMuted),
              onPressed: _pickCustom,
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        ResponsiveGrid(minTileWidth: 160, equalHeights: true, fill: true, children: [
          StatCard(label: 'Collected (paid)', value: Fmt.money(stats.sales), icon: Icons.account_balance_wallet_outlined, highlight: true, caption: '${stats.orders - stats.unpaid - stats.cancelled} paid bills'),
          StatCard(label: 'Billed (all orders)', value: Fmt.money(billed), icon: Icons.receipt_long_outlined, caption: '${period.length} orders', color: p.info),
          StatCard(label: 'Average bill', value: Fmt.money(stats.averageBill.round()), icon: Icons.payments_outlined, color: p.violet, caption: 'Per paid bill'),
          StatCard(label: 'Highest bill', value: Fmt.money(highest), icon: Icons.star_outline_rounded, color: p.warning, caption: 'Single bill'),
          StatCard(label: 'Discounts given', value: Fmt.money(discounts), icon: Icons.local_offer_outlined, color: p.primary, caption: 'Total off bills'),
        ]),
        const SizedBox(height: Space.lg),
        SectionCard(
          title: 'Sales trend',
          subtitle: 'Paid sales per day',
          icon: Icons.show_chart_rounded,
          child: SizedBox(height: 240, child: _TrendChart(points: daily)),
        ),
        _pair(
          context,
          SectionCard(
            title: 'Orders',
            icon: Icons.pie_chart_outline_rounded,
            child: Column(children: [
              _kv(context, 'Dine-in', '$dineIn'),
              _kv(context, 'Takeaway', '$takeaway'),
              _kv(context, 'Completed', '${stats.completed}'),
              _kv(context, 'Cancelled', '${stats.cancelled}'),
              _kv(context, 'Unpaid', '${stats.unpaid}'),
              const Divider(height: Space.xl),
              for (final m in PaymentMethod.values) _kv(context, 'Paid by ${m.label}', Fmt.money(stats.byMethod[m]!)),
            ]),
          ),
          SectionCard(
            title: 'Customers',
            icon: Icons.groups_outlined,
            child: Column(children: [
              _kv(context, 'Total customers (all time)', '${lifetime.keys.where((k) => k.isNotEmpty).length}'),
              _kv(context, 'Visited in this period', '${periodKeys.length}'),
              _kv(context, 'New', '${periodKeys.length - returning}'),
              _kv(context, 'Returning', '$returning'),
              if (topSpender != null) _kv(context, 'Top spender', '${names[topSpender.key]} · ${Fmt.money(topSpender.value)}'),
            ]),
          ),
        ),
        SectionCard(
          title: 'Top items',
          icon: Icons.emoji_events_outlined,
          padding: const EdgeInsets.fromLTRB(Space.lg + 4, Space.lg + 4, Space.lg + 4, Space.sm),
          child: topItems.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: Space.lg), child: Text('No sales in this period.', style: TextStyle(color: p.inkSubtle)))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Row(children: [
                      Expanded(child: Text('Item', style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600))),
                      SizedBox(width: 70, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600))),
                      SizedBox(width: 100, child: Text('Revenue', textAlign: TextAlign.right, style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                  for (final n in topItems.take(15))
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                      child: Row(children: [
                        Expanded(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 70, child: Text('${itemQty[n]}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                        SizedBox(width: 100, child: Text(Fmt.money(itemRev[n]!), textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
                      ]),
                    ),
                ]),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: context.palette.inkMuted))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      );

  Widget _pair(BuildContext context, Widget a, Widget b) {
    if (!context.isDesktop) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, b]);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: a),
        const SizedBox(width: Space.lg),
        Expanded(child: b),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxY = points.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final step = (points.length / 7).ceil().clamp(1, 31);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 100 : maxY * 1.2,
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(Fmt.money(v.round()), style: TextStyle(fontSize: 11, color: p.inkSubtle)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length || i % step != 0) return const SizedBox.shrink();
                final d = points[i].$1;
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d.day}/${d.month}', style: TextStyle(fontSize: 11, color: p.inkSubtle)));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.ink,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem('${Fmt.date(points[s.x.toInt()].$1)}\n${Fmt.money(s.y.round())}', TextStyle(color: p.surface, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: p.primary,
            barWidth: 3,
            dotData: FlDotData(show: points.length <= 14),
            belowBarData: BarAreaData(show: true, color: p.primary.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }
}
