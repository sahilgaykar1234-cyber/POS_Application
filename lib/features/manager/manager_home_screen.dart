import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../expenses/expenses.dart';
import '../orders/bill.dart';
import '../orders/order_details_sheet.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import '../settings/business_settings.dart';
import 'sales_stats.dart';

/// Manager's "Today" dashboard. Everything is for the signed-in cafe only.
class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key, required this.onNewOrder, required this.onOpenTables, this.ordersStream, this.expensesStream, this.settingsStream});
  final Stream<List<PosOrder>>? ordersStream;
  final Stream<List<Expense>>? expensesStream;
  final Stream<BusinessSettings>? settingsStream;
  final VoidCallback onNewOrder;
  final VoidCallback onOpenTables;

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchAll();
  late final _expenses = widget.expensesStream ?? ExpenseService.instance.watch();
  late final _settings = widget.settingsStream ?? BusinessSettingsRepository.instance.watch();

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: _settings,
      builder: (context, setSnap) => StreamBuilder<List<Expense>>(
        stream: _expenses,
        builder: (context, expSnap) => StreamBuilder<List<PosOrder>>(
          stream: _orders,
          builder: (context, snap) {
            if (snap.hasError) return const ErrorState();
            if (!snap.hasData) return const LoadingState(label: 'Loading today…');
            return _build(context, snap.data!, expSnap.data ?? const [], setSnap.data ?? BusinessSettings.empty);
          },
        ),
      ),
    );
  }

  Widget _build(BuildContext context, List<PosOrder> all, List<Expense> expenses, BusinessSettings settings) {
    final p = context.palette;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayOrders = SalesStats.between(all, today, today.add(const Duration(days: 1)));
    final lastWeek = SalesStats.between(all, today.subtract(const Duration(days: 7)), today.subtract(const Duration(days: 6)))
        .where((o) => o.createdAt!.hour <= now.hour)
        .toList();
    final s = SalesStats.of(todayOrders);
    final lw = SalesStats.of(lastWeek);
    final monthStart = DateTime(now.year, now.month);
    final monthSales = SalesStats.of(SalesStats.between(all, monthStart, DateTime(now.year, now.month + 1))).sales;
    final monthExpenses = expensesBetween(expenses, monthStart, DateTime(now.year, now.month + 1));

    String? vsLastWeek;
    if (lw.sales > 0) {
      final pct = ((s.sales - lw.sales) / lw.sales * 100).round();
      vsLastWeek = '${pct >= 0 ? '▲' : '▼'} ${pct.abs()}% vs last ${_weekdays[now.weekday - 1]}';
    }

    final recent = [...todayOrders]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    return PageBody(
      children: [
        PageHeader(
          title: settings.shopName.isEmpty ? 'Today' : settings.shopName,
          subtitle: '${_weekdays[now.weekday - 1]}, ${Fmt.date(now)}',
          actions: [
            OutlinedButton.icon(onPressed: widget.onOpenTables, icon: const Icon(Icons.table_restaurant_outlined, size: 18), label: const Text('Tables')),
            FilledButton.icon(onPressed: widget.onNewOrder, icon: const Icon(Icons.add, size: 18), label: const Text('New order')),
          ],
        ),
        ResponsiveGrid(
          minTileWidth: 170,
          children: [
            StatCard(label: "Today's sales", value: Fmt.money(s.sales), icon: Icons.trending_up_rounded, highlight: true, caption: vsLastWeek ?? 'Paid bills'),
            StatCard(label: 'Orders', value: '${s.orders}', icon: Icons.receipt_long_outlined, caption: 'Avg bill ${Fmt.money(s.averageBill.round())}', color: p.info),
            StatCard(label: 'Running', value: '${s.running}', icon: Icons.local_fire_department_outlined, color: p.warning, onTap: widget.onOpenTables, caption: 'Tap to open tables'),
            StatCard(label: 'Completed', value: '${s.completed}', icon: Icons.check_circle_outline, color: p.success),
            StatCard(label: 'Unpaid', value: '${s.unpaid}', icon: Icons.hourglass_bottom_rounded, color: s.unpaid > 0 ? p.danger : p.inkSubtle),
            StatCard(label: 'Cancelled', value: '${s.cancelled}', icon: Icons.cancel_outlined, color: p.inkSubtle),
          ],
        ),
        const SizedBox(height: Space.lg),
        _twoUp(
          context,
          SectionCard(
            title: 'Sales by hour',
            subtitle: 'Paid bills today',
            icon: Icons.bar_chart_rounded,
            child: SizedBox(height: 220, child: _HourlyChart(values: s.byHour, now: now)),
          ),
          SectionCard(
            title: 'Payment split',
            icon: Icons.donut_large_rounded,
            child: _PaymentSplit(byMethod: s.byMethod),
          ),
          flexA: 2,
        ),
        _twoUp(
          context,
          SectionCard(
            title: 'Best sellers today',
            icon: Icons.emoji_events_outlined,
            child: s.topItems.isEmpty
                ? Padding(padding: const EdgeInsets.symmetric(vertical: Space.lg), child: Text('No items sold yet.', style: TextStyle(color: p.inkSubtle)))
                : Column(children: [for (var i = 0; i < s.topItems.length; i++) _BestSeller(rank: i + 1, name: s.topItems[i].$1, qty: s.topItems[i].$2, max: s.topItems.first.$2)]),
          ),
          SectionCard(
            title: 'Last 7 days',
            subtitle: 'Paid sales per day',
            icon: Icons.show_chart_rounded,
            child: SizedBox(height: 200, child: _WeekChart(points: SalesStats.dailySales(all, now: now))),
          ),
        ),
        SectionCard(
          title: 'This month',
          icon: Icons.calendar_month_outlined,
          child: ResponsiveGrid(minTileWidth: 180, children: [
            _MiniStat(label: 'Sales', value: Fmt.money(monthSales), color: p.success),
            _MiniStat(label: 'Expenses', value: Fmt.money(monthExpenses), color: p.danger),
            _MiniStat(label: 'Profit (sales − expenses)', value: Fmt.money(monthSales - monthExpenses), color: monthSales - monthExpenses >= 0 ? p.success : p.danger),
          ]),
        ),
        SectionCard(
          title: 'Recent bills',
          icon: Icons.receipt_outlined,
          trailing: TextButton(onPressed: widget.onOpenTables, child: const Text('All tables')),
          padding: const EdgeInsets.fromLTRB(Space.lg + 4, Space.lg + 4, Space.lg + 4, Space.sm),
          child: recent.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: Space.lg), child: Text('No orders yet today.', style: TextStyle(color: p.inkSubtle)))
              : Column(
                  children: [
                    for (final o in recent.take(8))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: 56,
                        title: Text(o.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${o.billNo} · ${o.itemCount} items · ${Fmt.dateTime(o.createdAt).split(', ').last}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!context.isMobile) ...[
                              StatusChip(o.isActive ? o.statusLabel : (o.isPaid ? 'Paid' : o.statusLabel)),
                              const SizedBox(width: Space.md),
                            ],
                            MoneyText(o.totalPrice, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        onTap: o.isActive ? () => showOrderDetailsSheet(context, o, settings, canDelete: true) : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _twoUp(BuildContext context, Widget a, Widget b, {int flexA = 1}) {
    if (!context.isDesktop) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, b]);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: flexA, child: a),
          const SizedBox(width: Space.lg),
          Expanded(child: b),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.palette.inkSubtle, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
}

class _BestSeller extends StatelessWidget {
  const _BestSeller({required this.rank, required this.name, required this.qty, required this.max});
  final int rank;
  final String name;
  final int qty;
  final int max;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 24, child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: p.inkSubtle))),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
              Text('$qty sold', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(value: max == 0 ? 0 : qty / max, minHeight: 6, color: p.primary, backgroundColor: p.surfaceAlt),
          ),
        ],
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.values, required this.now});
  final List<double> values;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Show business hours: first hour with sales (or 10am) to current hour.
    var start = values.indexWhere((v) => v > 0);
    if (start < 0 || start > 10) start = start < 0 ? 10 : start;
    final end = (now.hour >= start ? now.hour : 23).clamp(start, 23);
    final hours = [for (var h = start; h <= end; h++) h];
    final maxY = hours.fold<double>(0, (m, h) => values[h] > m ? values[h] : m);

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 100 : maxY * 1.15,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY <= 0 ? 25 : maxY / 3,
          getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(Fmt.money(v.round()), style: TextStyle(fontSize: 11, color: p.inkSubtle)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final h = v.toInt();
                if (hours.length > 8 && h % 2 == 1) return const SizedBox.shrink();
                final label = h == 0 ? '12a' : (h < 12 ? '${h}a' : (h == 12 ? '12p' : '${h - 12}p'));
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(label, style: TextStyle(fontSize: 11, color: p.inkSubtle)));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => p.ink,
            getTooltipItem: (g, _, r, _) => BarTooltipItem(Fmt.money(r.toY.round()), TextStyle(color: p.surface, fontWeight: FontWeight.w700)),
          ),
        ),
        barGroups: [
          for (final h in hours)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(
                toY: values[h],
                width: hours.length > 12 ? 10 : 18,
                color: h == now.hour ? p.primary : p.primary.withValues(alpha: 0.45),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.points});
  final List<(DateTime, double)> points;

  static const _d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxY = points.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 100 : maxY * 1.2,
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_d[points[i].$1.weekday - 1], style: TextStyle(fontSize: 11, color: p.inkSubtle)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.ink,
            getTooltipItems: (spots) => [
              for (final s in spots) LineTooltipItem(Fmt.money(s.y.round()), TextStyle(color: p.surface, fontWeight: FontWeight.w700)),
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
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3.5, color: p.surface, strokeColor: p.primary, strokeWidth: 2),
            ),
            belowBarData: BarAreaData(show: true, color: p.primary.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }
}

class _PaymentSplit extends StatelessWidget {
  const _PaymentSplit({required this.byMethod});
  final Map<PaymentMethod, double> byMethod;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = byMethod.values.fold<double>(0, (s, v) => s + v);
    final colors = {PaymentMethod.cash: p.success, PaymentMethod.upi: p.primary, PaymentMethod.card: p.info};
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: total <= 0
              ? Center(child: Text('No payments yet', style: TextStyle(color: p.inkSubtle)))
              : PieChart(PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 44,
                  sections: [
                    for (final m in PaymentMethod.values)
                      if (byMethod[m]! > 0) PieChartSectionData(value: byMethod[m], color: colors[m], radius: 22, showTitle: false),
                  ],
                )),
        ),
        const SizedBox(height: Space.md),
        for (final m in PaymentMethod.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[m], shape: BoxShape.circle)),
                const SizedBox(width: Space.sm),
                Text(m.label),
                const Spacer(),
                Text(Fmt.money(byMethod[m]!), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
      ],
    );
  }
}
