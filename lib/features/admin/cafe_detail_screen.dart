import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_service.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';
import '../menu/menu_management_screen.dart';
import '../staff/staff_management_screen.dart';
import 'admin_service.dart';
import 'cafe_form_screen.dart';
import 'payment_list.dart';
import 'subscription_dialogs.dart';

/// Everything about one cafe for the Master Admin.
class CafeDetailScreen extends StatelessWidget {
  const CafeDetailScreen({super.key, required this.cafeId});
  final String cafeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CafeSummary?>(
      stream: AdminService.instance.watchCafe(cafeId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline, title: 'Could not load cafe'));
        }
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
        }
        final cafe = snap.data;
        if (cafe == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.storefront_outlined, title: 'Cafe not found'));
        }

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              title: Row(
                children: [
                  Flexible(child: Text(cafe.name, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 10),
                  StatusChip(cafe.status),
                ],
              ),
              actions: [
                if (!cafe.isDeleted)
                  IconButton(
                    tooltip: 'Edit details',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(fullscreenDialog: true, builder: (_) => CafeFormScreen(cafe: cafe)),
                    ),
                  ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.accent,
                tabs: [
                  Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Overview'),
                  Tab(icon: Icon(Icons.group_outlined, size: 18), text: 'Staff'),
                  Tab(icon: Icon(Icons.restaurant_menu, size: 18), text: 'Menu'),
                  Tab(icon: Icon(Icons.workspace_premium_outlined, size: 18), text: 'Subscription'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _OverviewTab(cafe: cafe),
                StaffManagementScreen(cafeId: cafe.id, cafeName: cafe.name, embedded: true),
                MenuManagementScreen(cafeId: cafe.id, readOnly: true),
                _SubscriptionTab(cafe: cafe),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.cafe});
  final CafeSummary cafe;

  Future<void> _setStatus(BuildContext context, String status, String verb) async {
    final blocking = status != CafeStatus.active;
    final ok = blocking
        ? await showDangerConfirmDialog(
            context,
            title: '$verb ${cafe.name}?',
            message: 'Staff of this cafe will not be able to use the POS until it is activated again. '
                'No data will be deleted.',
            confirmLabel: verb,
          )
        : true;
    if (!ok || !context.mounted) return;
    try {
      await AdminService.instance.setCafeStatus(cafe, status);
      if (context.mounted) showSuccess(context, 'Cafe is now ${status.toUpperCase()}');
    } catch (e) {
      if (context.mounted) showError(context, AuthService.friendlyError(e));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Delete ${cafe.name}?',
      message: 'The cafe will be closed and ALL its staff accounts disabled and signed out.\n\n'
          'Orders, menu and payment history are KEPT (soft delete) and the cafe can be restored later.',
      confirmLabel: 'Delete cafe',
      confirmText: cafe.name,
    );
    if (!ok || !context.mounted) return;
    try {
      final n = await AdminService.instance.deleteCafe(cafe.id, cafe.name);
      if (context.mounted) showSuccess(context, 'Cafe deleted. $n staff account(s) disabled.');
    } catch (e) {
      if (context.mounted) showError(context, AuthService.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = cafe.access(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!cafe.isDeleted && !access.canUsePos)
          Card(
            color: AppColors.danger.withValues(alpha: 0.12),
            child: ListTile(
              leading: const Icon(Icons.block, color: AppColors.danger),
              title: Text(access.title.isEmpty ? 'POS blocked' : access.title),
              subtitle: Text(access.message),
            ),
          ),
        SectionCard(
          title: 'Details',
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: InfoRow('Cafe ID', cafe.id)),
                  IconButton(
                    tooltip: 'Copy ID',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: cafe.id));
                      showSuccess(context, 'Cafe ID copied');
                    },
                  ),
                ],
              ),
              InfoRow('Owner', cafe.ownerName),
              InfoRow('Owner email', cafe.ownerEmail),
              InfoRow('Contact', cafe.contactNumber),
              InfoRow('Address', cafe.address),
              InfoRow('GSTIN', cafe.gstNumber),
              InfoRow('Created', Fmt.dateTime(cafe.data['createdAt'])),
              if (cafe.data['migratedAt'] != null) InfoRow('Data migrated', Fmt.dateTime(cafe.data['migratedAt'])),
              if (cafe.legacyData) const InfoRow('Data', 'Waiting for migration from the old database'),
            ],
          ),
        ),
        SectionCard(
          title: 'Cafe status',
          icon: Icons.toggle_on_outlined,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cafe.isDeleted
                ? [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore cafe'),
                      onPressed: () => _setStatus(context, CafeStatus.active, 'Restore'),
                    ),
                    const Text('Staff accounts stay disabled until you enable them in the Staff tab.',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]
                : [
                    if (cafe.status != CafeStatus.active)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Activate'),
                        onPressed: () => _setStatus(context, CafeStatus.active, 'Activate'),
                      ),
                    if (cafe.status != CafeStatus.inactive)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.pause),
                        label: const Text('Deactivate'),
                        onPressed: () => _setStatus(context, CafeStatus.inactive, 'Deactivate'),
                      ),
                    if (cafe.status != CafeStatus.suspended)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
                        icon: const Icon(Icons.block),
                        label: const Text('Suspend'),
                        onPressed: () => _setStatus(context, CafeStatus.suspended, 'Suspend'),
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      onPressed: () => _delete(context),
                    ),
                  ],
          ),
        ),
        SectionCard(
          title: 'Recent activity',
          icon: Icons.history,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: AdminService.instance.watchAuditLogs(cafeId: cafe.id, limit: 10),
            builder: (context, snap) {
              if (snap.hasError) return const Text('Activity unavailable (index may still be building).', style: TextStyle(color: Colors.white38));
              final logs = snap.data ?? const [];
              if (logs.isEmpty) return const Text('No activity yet.', style: TextStyle(color: Colors.white54));
              return Column(
                children: [
                  for (final l in logs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(describeAudit(l)),
                      subtitle: Text(Fmt.dateTime(l['at']), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  const _SubscriptionTab({required this.cafe});
  final CafeSummary cafe;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final expiry = cafe.expiryDate;
    final daysLeft = expiry?.difference(now).inDays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Current subscription',
          icon: Icons.workspace_premium_outlined,
          trailing: TextButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('Change'),
            onPressed: cafe.isDeleted ? null : () => showSetSubscriptionDialog(context, cafe),
          ),
          child: Column(
            children: [
              InfoRow('Plan', cafe.planName ?? 'Custom'),
              Row(children: [
                const SizedBox(width: 140, child: Text('Status', style: TextStyle(color: Colors.white54))),
                StatusChip(cafe.subscriptionStatus == '—' ? 'none' : cafe.subscriptionStatus),
                const SizedBox(width: 8),
                if (cafe.isOverdue(now)) const StatusChip('overdue'),
              ]),
              const SizedBox(height: 4),
              InfoRow('Start', Fmt.date(cafe.startDate)),
              InfoRow(
                'Expiry',
                expiry == null
                    ? 'No expiry set'
                    : '${Fmt.date(expiry)}${daysLeft != null && daysLeft >= 0 ? '  ($daysLeft days left)' : '  (ended)'}',
              ),
              InfoRow('Amount', Fmt.money(cafe.amount)),
              InfoRow('Payment', cafe.paymentStatus),
              InfoRow('Last payment', Fmt.date(cafe.subscription['lastPaymentAt'])),
            ],
          ),
        ),
        SectionCard(
          title: 'Payment history',
          icon: Icons.receipt_long_outlined,
          trailing: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Record payment'),
            onPressed: cafe.isDeleted
                ? null
                : () async {
                    final receipt = await showRecordPaymentDialog(context, cafe);
                    if (receipt != null && context.mounted) showSuccess(context, 'Payment recorded · $receipt');
                  },
          ),
          child: StreamBuilder<List<SubscriptionPayment>>(
            stream: AdminService.instance.watchPayments(cafeId: cafe.id),
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final list = snap.data!;
              final total = list.fold<double>(0, (s, p) => s + p.amount);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (list.isNotEmpty)
                    Text('Total received: ${Fmt.money(total)}',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                  PaymentList(payments: list, showCafe: false),
                ],
              );
            },
          ),
        ),
        const Text(
          'Note: these are subscription payments from the cafe to you. Customer bills (orders) are kept separately inside each cafe.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

/// Human-readable one-liner for an audit log entry.
String describeAudit(Map<String, dynamic> l) {
  final a = (l['action'] ?? '').toString();
  final d = l['details'] is Map ? Map<String, dynamic>.from(l['details']) : const <String, dynamic>{};
  return switch (a) {
    'cafe.create' => 'Cafe created${d['name'] != null ? ': ${d['name']}' : ''}',
    'cafe.update' => 'Cafe details edited',
    'cafe.status' => 'Status changed ${d['from'] ?? ''} → ${d['to'] ?? ''}',
    'cafe.delete' => 'Cafe deleted (${d['staffDisabled'] ?? 0} staff disabled)',
    'staff.invite' => 'Staff invited: ${d['email'] ?? ''} (${d['role'] ?? ''})',
    'staff.enable' => 'Staff account enabled',
    'staff.disable' => 'Staff account disabled',
    'staff.passwordReset' => 'Password reset sent',
    'subscription.set' => 'Subscription set: ${d['plan'] ?? 'custom'}, ${d['status'] ?? ''}, until ${d['expiry'] ?? ''}',
    'subscription.expired' => 'Subscription expired (${d['expiry'] ?? ''})',
    'payment.record' => 'Payment ${d['receiptNo'] ?? ''}: ${d['amount'] is num ? Fmt.money(d['amount'] as num) : ''} via ${d['method'] ?? ''}',
    'plan.create' => 'Plan created: ${d['name'] ?? ''}',
    'plan.update' => 'Plan updated: ${d['name'] ?? ''}',
    'migration.full' => 'Data migrated from old database',
    'migration.delta' => 'Late orders copied from old database (${d['ordersCopied'] ?? 0})',
    'superAdmin.bootstrap' => 'Super Admin account set up',
    _ => a,
  };
}
