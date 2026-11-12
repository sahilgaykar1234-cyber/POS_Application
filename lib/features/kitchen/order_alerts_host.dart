import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/web/alerts.dart';
import '../../core/widgets/ui.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import 'order_alerts.dart';

/// Wraps the Captain (kitchen) screen: when the Manager places an order or
/// adds items, a pop-up card slides in with a chime, and – if the browser
/// tab is in the background and alerts are allowed – a system notification.
class OrderAlertsHost extends StatefulWidget {
  const OrderAlertsHost({super.key, required this.child, this.ordersStream, this.chime, this.autoDismiss = const Duration(minutes: 2)});
  final Widget child;
  final Stream<List<PosOrder>>? ordersStream;

  /// Sound to play (defaults to the browser chime); replaceable in tests.
  final VoidCallback? chime;
  final Duration autoDismiss;

  @override
  State<OrderAlertsHost> createState() => _OrderAlertsHostState();
}

class _OrderAlertsHostState extends State<OrderAlertsHost> {
  final _detector = OrderAlertDetector();
  final List<OrderAlert> _alerts = [];
  final Map<String, Timer> _timers = {};
  StreamSubscription<List<PosOrder>>? _sub;

  static const _maxShown = 3;

  @override
  void initState() {
    super.initState();
    _sub = (widget.ordersStream ?? OrderService.instance.watchLive()).listen(_onOrders, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  String _key(OrderAlert a) => '${a.order.id}:${a.kind.name}';

  void _onOrders(List<PosOrder> orders) {
    final fresh = _detector.update(orders);
    // Orders that left "New" (cooking started elsewhere / deleted) need no pop-up.
    final pendingIds = {for (final o in orders) if (o.isActive && o.status == 'pending') o.id};
    final gone = _alerts.where((a) => !pendingIds.contains(a.order.id)).toList();
    if (fresh.isEmpty && gone.isEmpty) return;
    if (!mounted) return;
    setState(() {
      for (final a in gone) {
        _remove(a, rebuild: false);
      }
      for (final a in fresh) {
        _alerts.removeWhere((x) => x.order.id == a.order.id);
        _alerts.insert(0, a);
        final k = _key(a);
        _timers[k]?.cancel();
        _timers[k] = Timer(widget.autoDismiss, () => _remove(a));
      }
    });
    if (fresh.isNotEmpty) {
      (widget.chime ?? playOrderChime)();
      for (final a in fresh) {
        showSystemAlert(
          '${a.title} · ${a.where}',
          itemsSummary(a.kitchenItems),
          tag: a.order.id,
        );
      }
    }
  }

  void _remove(OrderAlert a, {bool rebuild = true}) {
    _timers.remove(_key(a))?.cancel();
    void drop() => _alerts.removeWhere((x) => _key(x) == _key(a));
    if (!rebuild) return drop();
    if (mounted) setState(drop);
  }

  Future<void> _startCooking(OrderAlert a) async {
    _remove(a);
    try {
      await OrderService.instance.setStatus(a.order.id, 'preparing');
    } catch (_) {
      if (mounted) showError(context, 'Could not update. Please check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = context.isMobile;
    final shown = _alerts.take(_maxShown).toList();
    final more = _alerts.length - shown.length;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (shown.isNotEmpty)
          Positioned(
            top: Space.md,
            right: mobile ? Space.md : Space.xl,
            left: mobile ? Space.md : null,
            child: SafeArea(
              child: SizedBox(
                width: mobile ? null : 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in shown)
                      Padding(
                        key: ValueKey(_key(a)),
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _AlertCard(
                          alert: a,
                          onDismiss: () => _remove(a),
                          onStart: () => _startCooking(a),
                        ),
                      ),
                    if (more > 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Chip(label: Text('+$more more new')),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onDismiss, required this.onStart});
  final OrderAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = alert.kitchenItems;
    final isNew = alert.kind == OrderAlertKind.newOrder;
    final accent = isNew ? p.primary : p.info;
    final note = alert.order.specialRequest;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -16 * (1 - t)), child: child),
      ),
      child: Material(
        key: Key('order-alert-${alert.order.id}'),
        color: p.surface,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: Radii.cardR, side: BorderSide(color: accent, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(isNew ? Icons.notifications_active_rounded : Icons.playlist_add_rounded, color: accent),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alert.title.toUpperCase(),
                            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                        Text(alert.where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        if (alert.order.takeawayName.isNotEmpty || alert.order.tableNo.isNotEmpty)
                          Text(alert.order.displayName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                    icon: Icon(Icons.close_rounded, color: p.inkSubtle, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final it in items.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '${it['qty'] ?? 1}× ${it['name']}${(it['size'] ?? 'Standard') != 'Standard' ? ' · ${it['size']}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (items.length > 4) Text('+${items.length - 4} more items', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Note: $note',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.warning, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    const SizedBox(height: Space.md),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onStart,
                          icon: const Icon(Icons.local_fire_department_outlined, size: 18),
                          label: const Text('Start cooking'),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      OutlinedButton(onPressed: onDismiss, child: const Text('OK')),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header button to allow system notifications (for when the tab is in the
/// background). Hidden where the browser doesn't support them.
class SystemAlertsButton extends StatefulWidget {
  const SystemAlertsButton({super.key});

  @override
  State<SystemAlertsButton> createState() => _SystemAlertsButtonState();
}

class _SystemAlertsButtonState extends State<SystemAlertsButton> {
  String _perm = systemAlertPermission;

  @override
  Widget build(BuildContext context) {
    if (!systemAlertsSupported) return const SizedBox.shrink();
    final on = _perm == 'granted';
    return IconButton(
      tooltip: on
          ? 'Order alerts are on'
          : _perm == 'denied'
              ? 'Notifications are blocked in the browser settings'
              : 'Turn on order alerts',
      onPressed: () async {
        playOrderChime(); // also unlocks sound in the browser
        if (on) {
          showSuccess(context, 'Order alerts are on. You will hear a chime for new orders.');
          return;
        }
        final r = await requestSystemAlerts();
        if (!mounted) return;
        setState(() => _perm = r);
        if (r == 'granted') {
          showSuccess(this.context, 'Order alerts turned on');
        } else {
          showError(this.context, 'Notifications are blocked. Allow them from the lock icon in the address bar.');
        }
      },
      icon: Icon(on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: on ? null : context.palette.warning),
    );
  }
}
