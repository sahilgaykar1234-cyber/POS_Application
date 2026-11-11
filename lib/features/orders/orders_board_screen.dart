import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../receipt_screen.dart';
import '../pos/pos_screen.dart';
import '../settings/business_settings.dart';
import 'order_details_sheet.dart';
import 'order_model.dart';
import 'order_service.dart';

/// Live floor view: numbered tables, virtual tables and today's completed bills.
class OrdersBoardScreen extends StatefulWidget {
  const OrdersBoardScreen({super.key, required this.canDelete, this.ordersStream, this.settingsStream});
  final bool canDelete;
  final Stream<List<PosOrder>>? ordersStream;
  final Stream<BusinessSettings>? settingsStream;

  @override
  State<OrdersBoardScreen> createState() => _OrdersBoardScreenState();
}

enum _Filter { all, preparing, ready, completed }

class _OrdersBoardScreenState extends State<OrdersBoardScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchAll();
  late final _settings = widget.settingsStream ?? BusinessSettingsRepository.instance.watch();
  _Filter _filter = _Filter.all;

  Future<void> _newOrder({String? table}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PosScreen(prefilledTable: table, standalone: true)));
  }

  Future<void> _addVirtual() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Virtual table'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For customers sitting at another shop or spot. Give it a name you will recognise.',
                style: TextStyle(color: ctx.palette.inkSubtle),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Spot name', hintText: 'e.g. Sharma Tea, Shop 4, V-1'),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Take order')),
        ],
      ),
    );
    if (name == null) return;
    await _newOrder(table: name.isEmpty ? 'V-${DateTime.now().minute}' : name);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: _settings,
      builder: (context, setSnap) {
        final settings = setSnap.data ?? BusinessSettings.empty;
        return StreamBuilder<List<PosOrder>>(
          stream: _orders,
          builder: (context, snap) {
            if (snap.hasError) return const ErrorState();
            if (!snap.hasData) return const LoadingState(label: 'Loading tables…');
            final today = todaysOrders(snap.data!);
            final board = TableBoard.build(today, settings.numberOfTables);
            final completed = today.where((o) => o.isCompleted).toList()
              ..sort((a, b) => (b.completedAt ?? b.createdAt ?? DateTime(0)).compareTo(a.completedAt ?? a.createdAt ?? DateTime(0)));

            final running = today.where((o) => o.isActive).length;
            final preparing = today.where((o) => o.status == 'preparing').length;
            final ready = today.where((o) => o.status == 'ready').length;

            return Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: context.isMobile
                  ? FloatingActionButton(onPressed: () => _newOrder(), tooltip: 'New order', child: const Icon(Icons.add))
                  : null,
              body: PageBody(
                maxWidth: 1400,
                children: [
                  PageHeader(
                    title: 'Tables',
                    subtitle: '$running running · $preparing preparing · $ready ready to pay',
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _addVirtual,
                        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                        label: const Text('Virtual table'),
                      ),
                      if (!context.isMobile)
                        FilledButton.icon(
                          onPressed: () => _newOrder(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New order'),
                        ),
                    ],
                  ),
                  FilterPills<_Filter>(
                    options: [
                      (_Filter.all, 'All tables'),
                      (_Filter.preparing, 'Preparing ($preparing)'),
                      (_Filter.ready, 'Payment pending ($ready)'),
                      (_Filter.completed, 'Completed (${completed.length})'),
                    ],
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: Space.md),
                  if (_filter != _Filter.completed) const _Legend(),
                  const SizedBox(height: Space.md),
                  if (_filter == _Filter.completed)
                    _CompletedList(orders: completed, settings: settings)
                  else
                    _TablesGrid(
                      board: board,
                      tableCount: settings.numberOfTables,
                      filter: _filter,
                      onFree: (t) => _newOrder(table: '$t'),
                      onOrder: (o) => showOrderDetailsSheet(context, o, settings, canDelete: widget.canDelete),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget dot(Color c, String l) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          l,
          style: TextStyle(fontSize: 12, color: p.inkSubtle, fontWeight: FontWeight.w500),
        ),
      ],
    );
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.sm,
      children: [
        dot(p.success, 'Free'),
        dot(p.warning, 'Ordered'),
        dot(p.info, 'Preparing'),
        dot(p.primary, 'Ready / pay'),
        dot(p.violet, 'Virtual'),
      ],
    );
  }
}

(Color, Color, String) _statusLook(BuildContext context, PosOrder? o, {bool virtual = false}) {
  final p = context.palette;
  if (o == null) return (p.success, p.surface, 'Free');
  return switch (o.status) {
    'preparing' => (p.info, p.infoTint, 'Preparing'),
    'ready' => (p.primary, p.primaryTint, 'Ready · pay'),
    _ => virtual ? (p.violet, p.violetTint, 'Ordered') : (p.warning, p.warningTint, 'Ordered'),
  };
}

class _TablesGrid extends StatelessWidget {
  const _TablesGrid({required this.board, required this.tableCount, required this.filter, required this.onFree, required this.onOrder});
  final TableBoard board;
  final int tableCount;
  final _Filter filter;
  final ValueChanged<int> onFree;
  final ValueChanged<PosOrder> onOrder;

  bool _show(PosOrder? o) => switch (filter) {
    _Filter.all => true,
    _Filter.preparing => o?.status == 'preparing',
    _Filter.ready => o?.status == 'ready',
    _Filter.completed => false,
  };

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var t = 1; t <= tableCount; t++) {
      final o = board.byTable[t];
      if (!_show(o)) continue;
      tiles.add(_TableTile(label: '$t', order: o, onTap: () => o == null ? onFree(t) : onOrder(o)));
    }
    for (final v in board.virtuals) {
      if (!_show(v)) continue;
      tiles.add(_TableTile(label: v.tableNo, order: v, virtual: true, onTap: () => onOrder(v)));
    }
    if (tiles.isEmpty) {
      return const EmptyState(
        icon: Icons.table_restaurant_outlined,
        title: 'No tables here',
        message: 'Nothing matches this filter right now.',
      );
    }
    return ResponsiveGrid(minTileWidth: context.isMobile ? 104 : 150, spacing: Space.md, maxColumns: 10, children: tiles);
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.label, required this.order, required this.onTap, this.virtual = false});
  final String label;
  final PosOrder? order;
  final VoidCallback onTap;
  final bool virtual;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (c, tint, text) = _statusLook(context, order, virtual: virtual);
    final o = order;
    return Material(
      color: o == null ? p.surface : tint,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardR,
        side: BorderSide(color: o == null ? p.border : c.withValues(alpha: 0.6), width: o == null ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 128,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: o == null ? p.inkSubtle : c),
                      ),
                    ),
                    if (o != null && o.isPaid) Icon(Icons.check_circle_rounded, size: 16, color: p.success),
                  ],
                ),
                const Spacer(),
                Text(
                  virtual ? label : 'T$label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: virtual ? 18 : 26, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: -0.5),
                ),
                if (o != null) ...[
                  Text(
                    Fmt.money(o.totalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  Row(
                    children: [
                      if (o.createdAt != null) TableTimer(start: o.createdAt!, stoppedAt: o.isPaid ? (o.paidAt ?? o.completedAt) : null),
                      Flexible(
                        child: Text(
                          ' · ${o.itemCount} items',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.inkSubtle),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    'Tap to order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.inkSubtle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedList extends StatelessWidget {
  const _CompletedList({required this.orders, required this.settings});
  final List<PosOrder> orders;
  final BusinessSettings settings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (orders.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No completed bills yet today');
    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            ListTile(
              minTileHeight: 60,
              title: Text(orders[i].displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${orders[i].billNo} · ${Fmt.dateTime(orders[i].completedAt ?? orders[i].createdAt)} · ${orders[i].paymentLabel}',
              ),
              trailing: MoneyText(orders[i].totalPrice, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentCompleteReceiptScreen(
                    orderData: orders[i].data,
                    orderId: orders[i].id,
                    businessSettings: settings.receiptSettings,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Live "time at table" counter. Runs from when the order was taken until it
/// is paid (then shows the stopped time with a tick). Nothing is stored: it is
/// worked out on screen from the order's own timestamps, so it disappears
/// (resets) when the table is freed.
class TableTimer extends StatefulWidget {
  const TableTimer({super.key, required this.start, this.stoppedAt});
  final DateTime start;
  final DateTime? stoppedAt;

  @override
  State<TableTimer> createState() => _TableTimerState();
}

class _TableTimerState extends State<TableTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TableTimer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.stoppedAt == null) {
      _t ??= Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final running = widget.stoppedAt == null;
    final end = widget.stoppedAt ?? DateTime.now();
    final color = running ? p.ink : p.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(running ? Icons.timer_outlined : Icons.check_circle_rounded, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          formatElapsed(end.difference(widget.start)),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// 0:45 · 12:05 · 1:02:09
String formatElapsed(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
