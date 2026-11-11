import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';

/// Kitchen display: New → Preparing → Ready. Same status updates as the
/// original Captain screen (status + kitchenStatus).
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key, this.ordersStream});
  final Stream<List<PosOrder>>? ordersStream;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchAll();
  Timer? _tick;
  String _mobileTab = 'pending';

  @override
  void initState() {
    super.initState();
    // Refresh "x min ago" every 30 s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _set(PosOrder o, String status) async {
    try {
      await OrderService.instance.setStatus(o.id, status);
    } catch (_) {
      if (mounted) showError(context, 'Could not update. Please check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PosOrder>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.hasError) return const ErrorState();
        if (!snap.hasData) return const LoadingState(label: 'Loading orders…');
        final active = snap.data!.where((o) => o.isActive).toList()
          ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        final cols = {
          'pending': active.where((o) => o.status == 'pending').toList(),
          'preparing': active.where((o) => o.status == 'preparing').toList(),
          'ready': active.where((o) => o.status == 'ready').toList(),
        };

        if (active.isEmpty) {
          return const EmptyState(
            icon: Icons.soup_kitchen_outlined,
            title: 'No active orders',
            message: 'New orders will appear here automatically.',
          );
        }

        if (context.isMobile) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'pending', label: Text('New ${cols['pending']!.length}')),
                    ButtonSegment(value: 'preparing', label: Text('Cooking ${cols['preparing']!.length}')),
                    ButtonSegment(value: 'ready', label: Text('Ready ${cols['ready']!.length}')),
                  ],
                  selected: {_mobileTab},
                  onSelectionChanged: (s) => setState(() => _mobileTab = s.first),
                ),
              ),
              Expanded(child: _column(context, _mobileTab, cols[_mobileTab]!, showHeader: false)),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final k in ['pending', 'preparing', 'ready']) ...[
                Expanded(child: _column(context, k, cols[k]!)),
                if (k != 'ready') const SizedBox(width: Space.lg),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _column(BuildContext context, String status, List<PosOrder> list, {bool showHeader = true}) {
    final p = context.palette;
    final (title, color) = switch (status) {
      'pending' => ('New orders', p.warning),
      'preparing' => ('Preparing', p.info),
      _ => ('Ready to serve', p.success),
    };
    return Container(
      decoration: showHeader ? BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.cardR) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    '${list.length}',
                    style: TextStyle(color: p.inkSubtle, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text('Nothing here', style: TextStyle(color: p.inkSubtle)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Space.md),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                    itemBuilder: (context, i) => _TicketCard(order: list[i], accent: color, onAdvance: _set),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.order, required this.accent, required this.onAdvance});
  final PosOrder order;
  final Color accent;
  final void Function(PosOrder, String) onAdvance;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = order;
    final mins = o.createdAt == null ? 0 : DateTime.now().difference(o.createdAt!).inMinutes;
    final late = mins >= 20 && o.status != 'ready';
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(o.displayName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: late ? p.dangerTint : p.surfaceAlt,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            '$mins min',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: late ? p.danger : p.inkSubtle),
                          ),
                        ),
                      ],
                    ),
                    if (o.hasNewItemsAdded)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'NEW ITEMS ADDED',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.primary, letterSpacing: 0.5),
                        ),
                      ),
                    const SizedBox(height: Space.sm),
                    for (final it in o.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text('${it['qty'] ?? 1}×', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                            Expanded(
                              child: Text(
                                '${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' · ${it['size']}' : ''}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  decoration: it['isDone'] == true ? TextDecoration.lineThrough : null,
                                  color: it['isDone'] == true ? p.inkSubtle : p.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (o.specialRequest.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: Space.sm),
                        padding: const EdgeInsets.all(Space.sm),
                        decoration: BoxDecoration(color: p.warningTint, borderRadius: Radii.controlR),
                        child: Row(
                          children: [
                            Icon(Icons.sticky_note_2_outlined, size: 16, color: p.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                o.specialRequest,
                                style: TextStyle(color: p.warning, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    if (o.status == 'pending')
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: p.info, foregroundColor: Colors.white),
                        onPressed: () => onAdvance(o, 'preparing'),
                        icon: const Icon(Icons.local_fire_department_outlined),
                        label: const Text('Start cooking'),
                      )
                    else if (o.status == 'preparing')
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
                        onPressed: () => onAdvance(o, 'ready'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark ready'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => onAdvance(o, 'preparing'),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Back to preparing'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
