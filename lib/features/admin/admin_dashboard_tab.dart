import 'package:flutter/material.dart';

import '../../core/subscription/cafe_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';

/// System-wide overview for the platform owner.
class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key, required this.onNavigate});

  /// Switch shell tab: 1 Cafes, 3 Payments.
  final void Function(int) onNavigate;

  @override
  Widget build(BuildContext context) {
    final svc = AdminService.instance;
    return StreamBuilder<List<CafeSummary>>(
      stream: svc.watchCafes(),
      builder: (context, cafesSnap) {
        if (cafesSnap.hasError) {
          return const EmptyState(icon: Icons.error_outline, title: 'Could not load data', message: 'Check your connection.');
        }
        if (!cafesSnap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

        final now = DateTime.now();
        final all = cafesSnap.data!.where((c) => !c.isDeleted).toList();
        final active = all.where((c) => c.status == CafeStatus.active && c.access(now).canUsePos).length;
        final inactive = all.length - active;
        final pending = all.where((c) => c.isPaymentPending(now)).toList();
        final overdue = all.where((c) => c.isOverdue(now)).toList();
        final expiringSoon = all.where((c) {
          final e = c.expiryDate;
          return e != null && e.isAfter(now) && e.difference(now).inDays < kExpiryWarningDays;
        }).toList();
        final recent = [...all]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('As of ${Fmt.dateTime(now)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            StreamBuilder<List<SubscriptionPayment>>(
              stream: svc.watchPayments(),
              builder: (context, paySnap) {
                final payments = paySnap.data ?? const [];
                final revenue = payments.fold<double>(0, (s, p) => s + p.amount);
                final thisMonth = payments
                    .where((p) => p.paidAt != null && p.paidAt!.year == now.year && p.paidAt!.month == now.month)
                    .fold<double>(0, (s, p) => s + p.amount);
                return StreamBuilder<Map<String, int>>(
                  stream: svc.watchStaffCounts(),
                  builder: (context, staffSnap) {
                    final staff = staffSnap.data ?? const {'manager': 0, 'captain': 0};
                    return ResponsiveGrid(children: [
                      StatCard(label: 'Total cafes', value: '${all.length}', icon: Icons.storefront, onTap: () => onNavigate(1)),
                      StatCard(label: 'Active cafes', value: '$active', icon: Icons.check_circle_outline, color: AppColors.success),
                      StatCard(label: 'Inactive / blocked', value: '$inactive', icon: Icons.pause_circle_outline, color: Colors.grey),
                      StatCard(
                        label: 'Subscription revenue',
                        value: Fmt.money(revenue),
                        icon: Icons.currency_rupee,
                        color: AppColors.success,
                        caption: 'This month: ${Fmt.money(thisMonth)}',
                        onTap: () => onNavigate(3),
                      ),
                      StatCard(
                        label: 'Pending payments',
                        value: '${pending.length}',
                        icon: Icons.hourglass_bottom,
                        color: AppColors.accent,
                        caption: pending.isEmpty ? null : Fmt.money(pending.fold<double>(0, (s, c) => s + c.amount)),
                      ),
                      StatCard(label: 'Overdue / expired', value: '${overdue.length}', icon: Icons.warning_amber_rounded, color: AppColors.danger),
                      StatCard(label: 'Managers', value: '${staff['manager']}', icon: Icons.badge_outlined, color: Colors.lightBlueAccent),
                      StatCard(label: 'Captains', value: '${staff['captain']}', icon: Icons.restaurant_outlined, color: Colors.purpleAccent),
                    ]);
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final attention = _AttentionCard(overdue: overdue, pending: pending, expiring: expiringSoon);
              final recentCard = _RecentCafesCard(cafes: recent.take(5).toList());
              final alerts = const _AlertsCard();
              if (c.maxWidth < 900) return Column(children: [attention, recentCard, alerts]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: [attention, alerts])),
                  const SizedBox(width: 14),
                  Expanded(child: recentCard),
                ],
              );
            }),
          ],
        );
      },
    );
  }
}

void _openCafe(BuildContext context, CafeSummary c) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => CafeDetailScreen(cafeId: c.id)));

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.overdue, required this.pending, required this.expiring});
  final List<CafeSummary> overdue, pending, expiring;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final c in overdue) _row(context, c, 'Expired ${Fmt.date(c.expiryDate)}', AppColors.danger),
      for (final c in expiring.where((c) => !overdue.contains(c)))
        _row(context, c, 'Expires ${Fmt.date(c.expiryDate)}', AppColors.accent),
      for (final c in pending.where((c) => !overdue.contains(c) && !expiring.contains(c)))
        _row(context, c, 'Payment pending ${Fmt.money(c.amount)}', AppColors.accent),
    ];
    return SectionCard(
      title: 'Needs attention',
      icon: Icons.notification_important_outlined,
      child: rows.isEmpty
          ? const Text('All subscriptions are in good standing. 🎉', style: TextStyle(color: Colors.white54))
          : Column(children: rows),
    );
  }

  Widget _row(BuildContext context, CafeSummary c, String text, Color color) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.circle, size: 10, color: color),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(text, style: TextStyle(color: color, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openCafe(context, c),
      );
}

class _RecentCafesCard extends StatelessWidget {
  const _RecentCafesCard({required this.cafes});
  final List<CafeSummary> cafes;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Recently added cafes',
      icon: Icons.new_releases_outlined,
      child: cafes.isEmpty
          ? const Text('No cafes yet. Add one from the Cafes tab.', style: TextStyle(color: Colors.white54))
          : Column(
              children: [
                for (final c in cafes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceAlt,
                      child: Icon(Icons.storefront, size: 16, color: AppColors.accent),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Added ${Fmt.date(c.createdAt)}', style: const TextStyle(fontSize: 12, color: Colors.white38)),
                    trailing: StatusChip(c.status),
                    onTap: () => _openCafe(context, c),
                  ),
              ],
            ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Subscription alerts',
      icon: Icons.notifications_outlined,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: AdminService.instance.watchAdminNotifications(limit: 10),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Text('Alerts unavailable (index may still be building).', style: TextStyle(color: Colors.white38));
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) return const Text('No alerts.', style: TextStyle(color: Colors.white54));
          return Column(
            children: [
              for (final n in list)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    n['type'] == 'subscription_expired' ? Icons.error_outline : Icons.schedule,
                    color: n['read'] == true ? Colors.white24 : (n['type'] == 'subscription_expired' ? AppColors.danger : AppColors.accent),
                  ),
                  title: Text((n['title'] ?? '').toString(),
                      style: TextStyle(fontWeight: n['read'] == true ? FontWeight.normal : FontWeight.w600)),
                  subtitle: Text('${n['message'] ?? ''}\n${Fmt.dateTime(n['createdAt'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  isThreeLine: true,
                  trailing: n['read'] == true
                      ? null
                      : IconButton(
                          tooltip: 'Mark as read',
                          icon: const Icon(Icons.done, size: 18),
                          onPressed: () => AdminService.instance.markNotificationRead(n['id'].toString()),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}
