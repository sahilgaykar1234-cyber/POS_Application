import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';
import '../orders/order_model.dart';
import '../receipt/bill_view.dart';
import '../orders/order_service.dart';
import '../orders/orders_board_screen.dart' show TableTimer;
import '../orders/settle_bill_sheet.dart';
import '../orders/whatsapp_bill.dart';
import '../orders/whatsapp_launch.dart';
import '../pos/pos_screen.dart';
import '../pos/print_helper.dart';
import '../settings/business_settings.dart';
import 'takeaway_board.dart';

/// Takeaway counter: token-based queue New → Preparing → Ready for pickup,
/// promised pickup times, "order ready" WhatsApp, and picked-up history.
class TakeawayScreen extends StatefulWidget {
  const TakeawayScreen({super.key, this.ordersStream, this.settingsStream});

  /// Test hooks (default: live Firestore).
  final Stream<List<PosOrder>>? ordersStream;
  final Stream<BusinessSettings>? settingsStream;

  @override
  State<TakeawayScreen> createState() => _TakeawayScreenState();
}

class _TakeawayScreenState extends State<TakeawayScreen> {
  late final _orders = widget.ordersStream ?? OrderService.instance.watchLive();
  late final _settings = widget.settingsStream ?? BusinessSettingsRepository.instance.watch();
  String _q = '';
  String _mobileCol = 'pending';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresh pickup countdowns every 30 s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _newTakeaway() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen(standalone: true, initialOrderType: 'Takeaway')));

  bool _match(PosOrder o) {
    if (_q.isEmpty) return true;
    final q = _q.replaceAll('#', '');
    return '${o.tokenNo ?? ''}' == q || o.takeawayName.toLowerCase().contains(q) || o.customerPhone.contains(q) || o.billNo.toLowerCase().contains(q);
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
            if (!snap.hasData) return const LoadingState(label: 'Loading takeaway orders…');
            final board = TakeawayBoard.from(todaysOrders(snap.data!));
            final now = DateTime.now();
            final late = [...board.incoming, ...board.preparing].where((o) => pickupStatus(o, now).state == PickupState.late).length;
            final cols = {
              'pending': board.incoming.where(_match).toList(),
              'preparing': board.preparing.where(_match).toList(),
              'ready': board.ready.where(_match).toList(),
            };

            // One "New takeaway" button at a time: the big one in the empty
            // state, otherwise the header button (FAB on phones).
            final empty = board.active == 0 && board.pickedUp.isEmpty;
            return Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: context.isMobile && !empty
                  ? FloatingActionButton.extended(onPressed: _newTakeaway, icon: const Icon(Icons.add), label: const Text('Takeaway'))
                  : null,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(context.isMobile ? Space.lg : Space.xl, Space.lg, context.isMobile ? Space.lg : Space.xl, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: Space.md,
                          runSpacing: Space.md,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Takeaway', style: context.isMobile ? context.text.headlineSmall : context.text.headlineMedium),
                                const SizedBox(height: 4),
                                Text(
                                  '${board.active} active · ${board.ready.length} ready for pickup · ${board.pickedUp.length} picked up today',
                                  style: TextStyle(color: context.palette.inkSubtle),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: Space.sm,
                              runSpacing: Space.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SearchField(
                                  width: context.isMobile ? null : 240,
                                  hint: 'Token, name or phone',
                                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                                ),
                                if (context.isTablet)
                                  OutlinedButton.icon(
                                    onPressed: () => showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (_) => SizedBox(
                                        height: MediaQuery.sizeOf(context).height * 0.7,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
                                          child: _PickedUp(orders: board.pickedUp, settings: settings),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                                    label: Text('Picked up (${board.pickedUp.length})'),
                                  ),
                                if (!context.isMobile && !empty)
                                  FilledButton.icon(onPressed: _newTakeaway, icon: const Icon(Icons.add, size: 18), label: const Text('New takeaway')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.md),
                        _SummaryStrip(board: board, late: late),
                        const SizedBox(height: Space.md),
                      ],
                    ),
                  ),
                  Expanded(
                    child: empty
                        ? EmptyState(
                            icon: Icons.shopping_bag_outlined,
                            title: 'No takeaway orders yet today',
                            message: 'Take a takeaway order — it gets a token number and appears here.',
                            action: FilledButton.icon(onPressed: _newTakeaway, icon: const Icon(Icons.add), label: const Text('New takeaway')),
                          )
                        : context.isMobile
                        ? _mobile(context, cols, board, settings)
                        : _desktop(context, cols, board, settings),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _desktop(BuildContext context, Map<String, List<PosOrder>> cols, TakeawayBoard board, BusinessSettings settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final k in ['pending', 'preparing', 'ready']) ...[
            Expanded(
              child: _Column(status: k, orders: cols[k]!, settings: settings),
            ),
            if (k != 'ready' || context.isDesktop) const SizedBox(width: Space.lg),
          ],
          if (context.isDesktop)
            SizedBox(
              width: 300,
              child: _PickedUp(orders: board.pickedUp, settings: settings),
            ),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context, Map<String, List<PosOrder>> cols, TakeawayBoard board, BusinessSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'pending', label: Text('New ${cols['pending']!.length}')),
              ButtonSegment(value: 'preparing', label: Text('Prep ${cols['preparing']!.length}')),
              ButtonSegment(value: 'ready', label: Text('Ready ${cols['ready']!.length}')),
              ButtonSegment(value: 'done', label: Text('Done ${board.pickedUp.length}')),
            ],
            selected: {_mobileCol},
            onSelectionChanged: (s) => setState(() => _mobileCol = s.first),
          ),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: _mobileCol == 'done'
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: _PickedUp(orders: board.pickedUp, settings: settings, showTitle: false),
                )
              : _Column(status: _mobileCol, orders: cols[_mobileCol]!, settings: settings, showHeader: false),
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.board, required this.late});
  final TakeawayBoard board;
  final int late;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tokens = readyTokens(board);
    Widget pill(IconData i, String text, Color c, Color tint) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 16, color: c),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        pill(Icons.campaign_outlined, tokens.isEmpty ? 'Ready: none' : 'Ready: ${tokens.map((t) => '#$t').join('  ')}', p.success, p.successTint),
        if (late > 0) pill(Icons.alarm, '$late running late', p.danger, p.dangerTint),
        pill(Icons.hourglass_bottom_rounded, '${board.incoming.length + board.preparing.length} in kitchen', p.info, p.infoTint),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.orders, required this.settings, this.showHeader = true});
  final String status;
  final List<PosOrder> orders;
  final BusinessSettings settings;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (title, color) = switch (status) {
      'pending' => ('New', p.warning),
      'preparing' => ('Preparing', p.info),
      _ => ('Ready for pickup', p.success),
    };
    return Container(
      decoration: showHeader ? BoxDecoration(color: p.surfaceAlt, borderRadius: Radii.cardR) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xs),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    '${orders.length}',
                    style: TextStyle(color: p.inkSubtle, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text('Nothing here', style: TextStyle(color: p.inkSubtle)),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(showHeader ? Space.md : Space.lg, Space.sm, showHeader ? Space.md : Space.lg, 96),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                    itemBuilder: (context, i) => _TakeawayCard(order: orders[i], settings: settings, accent: color),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TakeawayCard extends StatelessWidget {
  const _TakeawayCard({required this.order, required this.settings, required this.accent});
  final PosOrder order;
  final BusinessSettings settings;
  final Color accent;

  Future<void> _set(BuildContext context, String status) async {
    try {
      await OrderService.instance.setStatus(order.id, status);
    } catch (_) {
      if (context.mounted) showError(context, 'Could not update. Please check your connection.');
    }
  }

  Future<void> _pickedUp(BuildContext context) async {
    if (!order.isPaid) {
      // Take the payment first; "Paid & free table" completes it.
      await showSettleBillSheet(context, order, settings);
      return;
    }
    try {
      final data = await OrderService.instance.complete(order, assignBillNumber: settings.autoGenBillNumber);
      if (!context.mounted) return;
      showSuccess(context, '${order.tokenLabel} picked up');
      await showBill(context, order: data, orderId: order.id, settings: settings.receiptSettings);
    } catch (_) {
      if (context.mounted) showError(context, 'Could not complete. Please check your connection.');
    }
  }

  Future<void> _notifyReady(BuildContext context) async {
    final number = normalizeWhatsAppNumber(order.customerPhone);
    if (number == null) return showError(context, 'No valid mobile number on this order.');
    final ok = await openWhatsAppChat(
      number,
      buildReadyMessage(shopName: settings.shopName, customerName: order.takeawayName, token: order.tokenNo, billNo: order.billNo),
    );
    if (!ok && context.mounted) showError(context, 'Could not open WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = order;
    final pickup = pickupStatus(o, DateTime.now());
    final (pc, pt) = switch (pickup.state) {
      PickupState.late => (p.danger, p.dangerTint),
      PickupState.dueSoon => (p.warning, p.warningTint),
      _ => (p.inkSubtle, p.surfaceAlt),
    };
    final hasPhone = normalizeWhatsAppNumber(o.customerPhone) != null;

    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: Radii.controlR),
                  child: Column(
                    children: [
                      Text(
                        'TOKEN',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.8),
                      ),
                      Text(
                        o.tokenNo != null ? '#${o.tokenNo}' : o.billNo,
                        style: TextStyle(fontSize: o.tokenNo != null ? 26 : 14, fontWeight: FontWeight.w800, color: accent, height: 1.1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.takeawayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      if (o.customerPhone.isNotEmpty) Text(o.customerPhone, style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (o.pickupAt != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: pt, borderRadius: BorderRadius.circular(Radii.pill)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule_rounded, size: 12, color: pc),
                                  const SizedBox(width: 3),
                                  Text(
                                    pickup.label,
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pc),
                                  ),
                                ],
                              ),
                            ),
                          if (o.createdAt != null) TableTimer(start: o.createdAt!, stoppedAt: o.isPaid ? (o.paidAt ?? o.completedAt) : null),
                          StatusChip(o.isPaid ? 'Paid' : 'Unpaid', color: o.isPaid ? p.success : p.warning, tint: o.isPaid ? p.successTint : p.warningTint),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            for (final it in o.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${it['qty'] ?? 1}×', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(
                        '${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' · ${it['size']}' : ''}',
                        style: TextStyle(color: p.inkMuted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (o.specialRequest.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Note: ${o.specialRequest}',
                  style: TextStyle(color: p.warning, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            Divider(height: Space.lg, color: p.border),
            Row(
              children: [
                MoneyText(o.totalPrice, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                if (o.status == 'ready' && hasPhone)
                  IconButton(
                    tooltip: 'Tell customer it\'s ready (WhatsApp)',
                    onPressed: () => _notifyReady(context),
                    icon: const Icon(Icons.chat_rounded, color: Color(0xFF128C4A)),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) async {
                    switch (v) {
                      case 'add':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PosScreen(editing: o, standalone: true)));
                      case 'print':
                        printBill(context, order: o.data, settings: settings.receiptSettings, orderId: o.id);
                      case 'pay':
                        showSettleBillSheet(context, o, settings);
                      case 'back':
                        _set(context, o.status == 'ready' ? 'preparing' : 'pending');
                      case 'delete':
                        final ok = await showDangerConfirmDialog(
                          context,
                          title: 'Delete ${o.tokenLabel}?',
                          message: '${o.takeawayName} · ${Fmt.money(o.totalPrice)}\nThis cannot be undone.',
                          confirmLabel: 'Delete',
                        );
                        if (ok) await OrderService.instance.delete(o.id, data: o.data);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'add', child: Text('Add items')),
                    const PopupMenuItem(value: 'print', child: Text('Print bill / token')),
                    if (!o.isPaid) const PopupMenuItem(value: 'pay', child: Text('Take payment')),
                    if (o.status != 'pending') const PopupMenuItem(value: 'back', child: Text('Move back')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: p.danger)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            if (o.status == 'pending')
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.info,
                  side: BorderSide(color: p.info),
                ),
                onPressed: () => _set(context, 'preparing'),
                icon: const Icon(Icons.local_fire_department_outlined, size: 18),
                label: const Text('Start preparing'),
              )
            else if (o.status == 'preparing')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: context.onStatusFill),
                onPressed: () => _set(context, 'ready'),
                icon: const Icon(Icons.room_service_outlined, size: 18),
                label: const Text('Mark ready'),
              )
            else
              FilledButton.icon(
                onPressed: () => _pickedUp(context),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text(o.isPaid ? 'Picked up' : 'Take payment & hand over'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickedUp extends StatelessWidget {
  const _PickedUp({required this.orders, required this.settings, this.showTitle = true});
  final List<PosOrder> orders;
  final BusinessSettings settings;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = orders.fold<double>(0, (s, o) => s + o.totalPrice);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
              child: Row(
                children: [
                  Icon(Icons.task_alt_rounded, size: 18, color: p.success),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text('Picked up today', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              '${orders.length} ${orders.length == 1 ? 'order' : 'orders'} · ${Fmt.money(total)}',
              style: TextStyle(color: p.inkSubtle, fontSize: 12),
            ),
          ),
          Divider(height: Space.lg, color: p.border),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text('None yet', style: TextStyle(color: p.inkSubtle)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${o.tokenLabel} · ${o.takeawayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${Fmt.dateTime(o.completedAt ?? o.createdAt).split(', ').last} · ${o.paymentLabel}'),
                        trailing: MoneyText(o.totalPrice, style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => showBill(context, order: o.data, orderId: o.id, settings: settings.receiptSettings),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
