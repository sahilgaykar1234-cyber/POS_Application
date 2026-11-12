import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import 'cafe_detail_screen.dart';
import '../../core/utils/friendly_error.dart';

/// Platform overview. Every number comes from Firestore; when there is no
/// data the card says so instead of showing a made-up figure.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, required this.data, required this.onNavigate, this.auditStream, this.now});
  final ValueListenable<AdminData> data;
  final ValueChanged<int> onNavigate;
  final Stream<List<Map<String, dynamic>>>? auditStream;
  final DateTime? now;

  static const cafesTab = 1, subscriptionsTab = 3, paymentsTab = 4, alertsTab = 5, activityTab = 6;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: data,
      builder: (context, d, _) {
        if (d.error != null && d.cafes.isEmpty) return ErrorState(message: friendlyError(d.error, 'load the platform data'));
        if (d.loading && d.cafes.isEmpty) return const LoadingState(label: 'Loading platform…');
        final now = this.now ?? DateTime.now();
        final s = PlatformStats.of(cafes: d.cafes, staff: d.staff, payments: d.payments, now: now);
        final alerts = computeAlerts(cafes: d.cafes, staff: d.staff, now: now, settings: d.settings);
        final p = context.palette;

        return PageBody(
          children: [
            PageHeader(
              title: 'Platform overview',
              subtitle: '${d.settings.platformName} · ${Fmt.date(now)}',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => onNavigate(alertsTab),
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: Text('Alerts (${alerts.length})'),
                ),
                FilledButton.icon(onPressed: () => onNavigate(cafesTab), icon: const Icon(Icons.storefront_outlined, size: 18), label: const Text('Cafes')),
              ],
            ),
            ResponsiveGrid(
              minTileWidth: 160,
              equalHeights: true,
              fill: true,
              maxColumns: 5,
              children: [
                StatCard(
                  label: 'Total cafes',
                  value: '${s.totalCafes}',
                  icon: Icons.storefront_outlined,
                  highlight: true,
                  caption: '${s.activeCafes} active · ${s.inactiveCafes} inactive',
                  onTap: () => onNavigate(cafesTab),
                ),
                StatCard(label: 'Active cafes', value: '${s.activeCafes}', icon: Icons.check_circle_outline, color: p.success, caption: 'Can use the POS'),
                StatCard(
                  label: 'Inactive cafes',
                  value: '${s.inactiveCafes}',
                  icon: Icons.pause_circle_outline,
                  color: s.inactiveCafes > 0 ? p.warning : p.inkSubtle,
                  caption: 'Deactivated or suspended',
                ),
                StatCard(label: 'Trial cafes', value: '${s.trialCafes}', icon: Icons.hourglass_top_rounded, color: p.info, caption: 'On a free trial'),
                StatCard(
                  label: 'Logins',
                  value: '${s.managers + s.captains}',
                  icon: Icons.badge_outlined,
                  color: p.violet,
                  caption: '${s.managers} manager · ${s.captains} captain',
                ),
                StatCard(
                  label: 'Active subscriptions',
                  value: '${s.activeSubscriptions}',
                  icon: Icons.verified_outlined,
                  color: p.success,
                  caption: 'Paid plans running',
                  onTap: () => onNavigate(subscriptionsTab),
                ),
                StatCard(
                  label: 'Expired',
                  value: '${s.expiredSubscriptions}',
                  icon: Icons.event_busy_outlined,
                  color: s.expiredSubscriptions > 0 ? p.danger : p.inkSubtle,
                  caption: s.expiredSubscriptions > 0 ? 'POS blocked' : 'None',
                ),
                StatCard(
                  label: 'MRR',
                  value: s.hasRevenueData ? Fmt.money(s.mrr.round()) : '—',
                  icon: Icons.trending_up_rounded,
                  color: p.primary,
                  caption: s.hasRevenueData ? 'From running paid plans' : 'No paid plans assigned yet',
                ),
                StatCard(
                  label: 'Payments collected',
                  value: s.paymentCount > 0 ? Fmt.money(s.totalCollected.round()) : '—',
                  icon: Icons.account_balance_wallet_outlined,
                  color: p.success,
                  caption: s.paymentCount > 0 ? '${s.paymentCount} recorded payment${s.paymentCount == 1 ? '' : 's'}' : 'No payments recorded yet',
                  onTap: () => onNavigate(paymentsTab),
                ),
                StatCard(
                  label: 'Need attention',
                  value: '${alerts.where((a) => a.level != AlertLevel.info).length}',
                  icon: Icons.priority_high_rounded,
                  color: p.danger,
                  caption: 'Expired, expiring, unpaid',
                  onTap: () => onNavigate(alertsTab),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            _pair(
              context,
              SectionCard(
                title: 'Cafe onboarding',
                subtitle: 'New cafes per month',
                icon: Icons.add_business_outlined,
                child: SizedBox(
                  height: 200,
                  child: MonthlyBars(
                    points: monthlySeries(d.cafes, dateOf: (c) => c.createdAt, now: now),
                    emptyText: 'No cafes yet',
                  ),
                ),
              ),
              SectionCard(
                title: 'Subscription status',
                icon: Icons.donut_small_outlined,
                child: _StatusBreakdown(by: s.bySubState, total: s.totalCafes),
              ),
            ),
            _pair(
              context,
              SectionCard(
                title: 'Subscription revenue',
                subtitle: 'Recorded payments per month',
                icon: Icons.payments_outlined,
                child: SizedBox(
                  height: 200,
                  child: MonthlyBars(
                    points: monthlySeries(d.payments.where((x) => x.status != 'refunded'), dateOf: (x) => x.paidAt, valueOf: (x) => x.amount, now: now),
                    money: true,
                    emptyText: 'No payments recorded yet',
                  ),
                ),
              ),
              SectionCard(
                title: 'Needs attention',
                icon: Icons.notifications_active_outlined,
                trailing: TextButton(onPressed: () => onNavigate(alertsTab), child: const Text('All alerts')),
                child: alerts.isEmpty
                    ? const InlineEmpty('All good. Nothing needs attention.', icon: Icons.task_alt_rounded)
                    : Column(
                        children: [for (final a in alerts.take(5)) AlertTile(alert: a, data: data)],
                      ),
              ),
            ),
            _pair(
              context,
              SectionCard(
                title: 'Recent cafes',
                icon: Icons.storefront_outlined,
                trailing: TextButton(onPressed: () => onNavigate(cafesTab), child: const Text('All cafes')),
                child: () {
                  final recent = [...d.cafes.where((c) => !c.isDeleted)]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
                  if (recent.isEmpty) return const InlineEmpty('No cafes yet');
                  return Column(
                    children: [
                      for (final c in recent.take(5))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Joined ${fmt(c.createdAt)}${c.location.isEmpty ? '' : ' · ${c.location}'}'),
                          trailing: SubStateChip(c.subState(now)),
                          onTap: () => openCafe(context, c.id, data),
                        ),
                    ],
                  );
                }(),
              ),
              SectionCard(
                title: 'Recent activity',
                subtitle: 'Subscriptions and payments',
                icon: Icons.history_rounded,
                trailing: TextButton(onPressed: () => onNavigate(activityTab), child: const Text('Activity log')),
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: auditStream ?? AdminService.instance.watchAuditLogs(limit: 60),
                  builder: (context, snap) {
                    final items = (snap.data ?? const [])
                        .where(
                          (e) => (e['action'] ?? '').toString().startsWith('subscription.') || e['action'] == 'payment.record' || e['action'] == 'cafe.create',
                        )
                        .take(6)
                        .toList();
                    if (!snap.hasData) {
                      return const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator()));
                    }
                    if (items.isEmpty) return const InlineEmpty('No subscription or payment activity yet');
                    return Column(
                      children: [
                        for (final e in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(_activityIcon(e['action'].toString()), color: context.palette.inkSubtle),
                            title: Text(
                              '${auditLabel(e['action'].toString())} · ${d.cafeName(e['cafeId']?.toString())}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(Fmt.dateTime(e['at'])),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String fmt(DateTime? d) => d == null ? '—' : Fmt.date(d);

  static IconData _activityIcon(String a) => switch (a) {
    'payment.record' => Icons.payments_outlined,
    'cafe.create' => Icons.add_business_outlined,
    'subscription.cancel' => Icons.cancel_outlined,
    'subscription.renew' => Icons.autorenew_rounded,
    _ => Icons.workspace_premium_outlined,
  };

  Widget _pair(BuildContext context, Widget a, Widget b) {
    if (!context.isDesktop) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, b]);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: Space.lg),
          Expanded(child: b),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.by, required this.total});
  final Map<SubState, int> by;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (total == 0) return const InlineEmpty('No cafes yet');
    final colors = {
      SubState.active: p.success,
      SubState.trial: p.info,
      SubState.pending: p.warning,
      SubState.cancelled: p.warning,
      SubState.expired: p.danger,
      SubState.suspended: p.danger,
      SubState.none: p.borderStrong,
    };
    return Column(
      children: [
        for (final s in SubState.values)
          if ((by[s] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: colors[s], shape: BoxShape.circle),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text(s.label)),
                      Text('${by[s]}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(value: by[s]! / total, minHeight: 6, color: colors[s], backgroundColor: p.surfaceAlt),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// One alert row (dashboard and Alerts screen).
class AlertTile extends StatelessWidget {
  const AlertTile({super.key, required this.alert, required this.data});
  final AdminAlert alert;
  final ValueListenable<AdminData> data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = switch (alert.level) {
      AlertLevel.critical => (Icons.error_rounded, p.danger),
      AlertLevel.warning => (Icons.warning_amber_rounded, p.warning),
      AlertLevel.info => (Icons.info_outline_rounded, p.info),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(alert.message),
      trailing: alert.cafeId == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: alert.cafeId == null ? null : () => openCafe(context, alert.cafeId!, data),
    );
  }
}
