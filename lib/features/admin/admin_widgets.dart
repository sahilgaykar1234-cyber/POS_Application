import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/subscription/cafe_access.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';

/// Small shared pieces of the Super Admin panel.

class SubStateChip extends StatelessWidget {
  const SubStateChip(this.state, {super.key});
  final SubState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (c, t) = switch (state) {
      SubState.active => (p.success, p.successTint),
      SubState.trial => (p.info, p.infoTint),
      SubState.pending || SubState.cancelled => (p.warning, p.warningTint),
      SubState.expired || SubState.suspended => (p.danger, p.dangerTint),
      SubState.none => (p.inkSubtle, p.surfaceAlt),
    };
    return StatusChip(state.label, color: c, tint: t);
  }
}

class CafeStatusChip extends StatelessWidget {
  const CafeStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (c, t) = switch (status) {
      CafeStatus.active => (p.success, p.successTint),
      CafeStatus.suspended || CafeStatus.deleted => (p.danger, p.dangerTint),
      _ => (p.inkSubtle, p.surfaceAlt),
    };
    return StatusChip(status[0].toUpperCase() + status.substring(1), color: c, tint: t);
  }
}

/// Explains an action that needs the admin script (Admin SDK) and shows the
/// exact command with a copy button. Nothing is run from the app.
Future<void> showAdminCommand(BuildContext context, {required String title, required String why, required String command}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(why, style: TextStyle(color: p.inkMuted)),
              const SizedBox(height: Space.md),
              Text('Run on your computer, in the project folder:', style: TextStyle(color: p.inkSubtle, fontSize: 13)),
              const SizedBox(height: Space.xs),
              Container(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.controlR, border: Border.all(color: p.border)),
                child: Row(children: [
                  Expanded(
                    child: SelectableText(
                      '$adminScriptEnv \\\n  $command',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                    ),
                  ),
                  IconButton(
                    key: const Key('copy-command'),
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '$adminScriptEnv $command'));
                      if (ctx.mounted) showSuccess(ctx, 'Command copied');
                    },
                  ),
                ]),
              ),
              const SizedBox(height: Space.sm),
              Text('Replace the words in <angle brackets>. Passwords are never stored by the app.',
                  style: TextStyle(color: p.inkSubtle, fontSize: 12)),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      );
    },
  );
}

/// Bars for a monthly series; a clear empty state when every value is 0.
class MonthlyBars extends StatelessWidget {
  const MonthlyBars({super.key, required this.points, this.money = false, this.emptyText = 'No data yet'});
  final List<(DateTime, double)> points;
  final bool money;
  final String emptyText;

  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxY = points.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    if (maxY <= 0) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.cardR),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insights_outlined, color: p.inkSubtle),
          const SizedBox(height: Space.xs),
          Text(emptyText, style: TextStyle(color: p.inkSubtle)),
        ]),
      );
    }
    return BarChart(BarChartData(
      maxY: maxY * 1.2,
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: maxY / 3, getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: money ? 56 : 28,
            getTitlesWidget: (v, meta) => v == meta.max
                ? const SizedBox.shrink()
                : Text(money ? Fmt.money(v.round()) : v.round().toString(), style: TextStyle(fontSize: 11, color: p.inkSubtle)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= points.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_m[points[i].$1.month - 1], style: TextStyle(fontSize: 11, color: p.inkSubtle)));
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => p.ink,
          getTooltipItem: (g, _, r, _) => BarTooltipItem(money ? Fmt.money(r.toY.round()) : r.toY.round().toString(), TextStyle(color: p.surface, fontWeight: FontWeight.w700)),
        ),
      ),
      barGroups: [
        for (var i = 0; i < points.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: points[i].$2, width: 22, color: p.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          ]),
      ],
    ));
  }
}

/// Label: value rows for detail sections.
class KvList extends StatelessWidget {
  const KvList(this.rows, {super.key, this.labelWidth = 150});
  final List<(String, String)> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: labelWidth, child: Text(r.$1, style: TextStyle(color: p.inkSubtle, fontSize: 13))),
            Expanded(child: SelectableText(r.$2.isEmpty ? '—' : r.$2, style: const TextStyle(fontWeight: FontWeight.w500))),
          ]),
        ),
    ]);
  }
}

/// A plain list empty state that fits inside cards.
class InlineEmpty extends StatelessWidget {
  const InlineEmpty(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: Column(children: [
          Icon(icon, color: context.palette.inkSubtle),
          const SizedBox(height: Space.xs),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.palette.inkSubtle)),
        ]),
      );
}

String daysLeftLabel(int? d) {
  if (d == null) return 'No end date';
  if (d < 0) return '${-d} day${d == -1 ? '' : 's'} ago';
  if (d == 0) return 'Today';
  return '$d day${d == 1 ? '' : 's'} left';
}
