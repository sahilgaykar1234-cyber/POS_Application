import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/business_day.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_dialogs.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import '../../core/utils/friendly_error.dart';

void openCafe(BuildContext context, String cafeId, ValueListenable<AdminData> data) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CafeDetailScreen(cafeId: cafeId, data: data),
  ),
);

/// One cafe: everything the Super Admin needs, only this cafe's data.
class CafeDetailScreen extends StatelessWidget {
  const CafeDetailScreen({super.key, required this.cafeId, required this.data, this.settingsStream, this.auditStream, this.historyStream, this.ops});
  final String cafeId;
  final ValueListenable<AdminData> data;

  // Tests can pass fixed data.
  final Stream<Map<String, dynamic>>? settingsStream;
  final Stream<List<Map<String, dynamic>>>? auditStream;
  final Stream<List<Map<String, dynamic>>>? historyStream;
  final Future<CafeOpsSummary>? ops;

  static const tabs = ['Overview', 'Information', 'Staff', 'Menu & sales', 'Subscription', 'Payments', 'Activity'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: data,
      builder: (context, d, _) {
        final cafe = d.cafe(cafeId);
        if (cafe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: d.loading ? const LoadingState() : const EmptyState(icon: Icons.storefront_outlined, title: 'Cafe not found'),
          );
        }
        final now = DateTime.now();
        return StreamBuilder<Map<String, dynamic>>(
          stream: settingsStream ?? AdminService.instance.watchCafeSettings(cafeId),
          builder: (context, set) {
            final settings = set.data ?? const <String, dynamic>{};
            final dayEnds = BusinessDay.parse(settings['dayEndsAt']) ?? BusinessDay.defaultCutoffMinutes;
            return DefaultTabController(
              length: tabs.length,
              child: Scaffold(
                backgroundColor: context.palette.canvas,
                appBar: AppBar(
                  // Title, tabs and page content all start at the same left edge.
                  titleSpacing: context.isMobile ? Space.lg : Space.xl,
                  title: Text(cafe.name),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: Space.md),
                      child: CafeStatusChip(cafe.status),
                    ),
                  ],
                  bottom: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: EdgeInsets.only(left: (context.isMobile ? Space.lg : Space.xl) - 16),
                    tabs: [for (final t in tabs) Tab(text: t)],
                  ),
                ),
                body: TabBarView(
                  children: [
                    _Overview(cafe: cafe, d: d, dayEnds: dayEnds, now: now),
                    _Info(cafe: cafe, settings: settings, dayEnds: dayEnds, d: d),
                    _Staff(cafe: cafe, d: d),
                    _MenuSales(cafeId: cafeId, dayEnds: dayEnds, ops: ops),
                    _Subscription(cafe: cafe, d: d, now: now, history: historyStream ?? AdminService.instance.watchSubscriptionHistory(cafeId)),
                    _Payments(cafe: cafe, d: d),
                    _Activity(stream: auditStream ?? AdminService.instance.watchAuditLogs(cafeId: cafeId)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Full width, same left edge as the title and tabs above.
Widget _page(List<Widget> children) => PageBody(maxWidth: double.infinity, bottomPadding: Space.xxl, children: children);

class _Overview extends StatelessWidget {
  const _Overview({required this.cafe, required this.d, required this.dayEnds, required this.now});
  final CafeSummary cafe;
  final AdminData d;
  final int dayEnds;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final st = cafe.subState(now);
    final logins = d.staff.where((s) => s.cafeId == cafe.id).toList();
    final access = cafe.access(now);
    return _page([
      ResponsiveGrid(
        minTileWidth: 200,
        equalHeights: true,
        fill: true,
        children: [
          StatCard(
            label: 'POS access',
            value: access.canUsePos ? 'Allowed' : 'Blocked',
            icon: Icons.point_of_sale_outlined,
            color: access.canUsePos ? p.success : p.danger,
            caption: access.title.isNotEmpty ? access.title : (access.message.isEmpty ? 'Working normally' : access.message),
          ),
          StatCard(label: 'Subscription', value: st.label, icon: Icons.workspace_premium_outlined, color: p.info, caption: cafe.planName ?? 'No plan assigned'),
          StatCard(
            label: 'Ends',
            value: cafe.expiryDate == null ? '—' : Fmt.date(cafe.expiryDate),
            icon: Icons.event_outlined,
            color: p.warning,
            caption: daysLeftLabel(cafe.daysLeft(now)),
          ),
          StatCard(
            label: 'Logins',
            value: '${logins.where((s) => s.isActive).length}',
            icon: Icons.badge_outlined,
            color: p.violet,
            caption: logins.isEmpty ? 'No login yet' : '${logins.length} total',
          ),
        ],
      ),
      const SizedBox(height: Space.lg),
      SectionCard(
        title: 'Actions',
        icon: Icons.bolt_outlined,
        child: Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            OutlinedButton.icon(
              key: const Key('cafe-edit'),
              onPressed: () => showCafeForm(context, cafe: cafe, currentDayEndsAt: dayEnds, platform: d.settings, plans: d.plans),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit details'),
            ),
            OutlinedButton.icon(
              onPressed: () => showAssignPlan(context, cafe, d.plans),
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: Text(cafe.hasSubscription ? 'Change plan' : 'Assign plan'),
            ),
            if (cafe.hasSubscription)
              OutlinedButton.icon(onPressed: () => showRenew(context, cafe), icon: const Icon(Icons.autorenew_rounded, size: 18), label: const Text('Renew')),
            OutlinedButton.icon(
              onPressed: () => showRecordPayment(context, d.cafes, cafe: cafe),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record payment'),
            ),
            OutlinedButton.icon(
              onPressed: () => showAdminCommand(context, title: 'Add a login for ${cafe.name}', why: kLoginHelp, command: loginCommand(cafe.id)),
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: const Text('Add login'),
            ),
            if (cafe.isActive) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.warning),
                onPressed: () => confirmCafeStatus(context, cafe, CafeStatus.inactive),
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: const Text('Deactivate'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                onPressed: () => confirmCafeStatus(context, cafe, CafeStatus.suspended),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Suspend'),
              ),
            ] else
              FilledButton.icon(
                onPressed: () => confirmCafeStatus(context, cafe, CafeStatus.active),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('Activate'),
              ),
            if (cafe.hasSubscription && st.running && st != SubState.cancelled)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                onPressed: () => confirmCancelSubscription(context, cafe),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel subscription'),
              ),
          ],
        ),
      ),
      SectionCard(
        title: 'At a glance',
        icon: Icons.storefront_outlined,
        child: KvList([
          ('Cafe ID', cafe.id),
          ('Owner', cafe.ownerName),
          ('Phone', cafe.contactNumber),
          ('Location', cafe.location),
          ('Business day ends', BusinessDay.label(dayEnds)),
          ('Created', fmtDate(cafe.createdAt)),
        ]),
      ),
    ]);
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.cafe, required this.settings, required this.dayEnds, required this.d});
  final CafeSummary cafe;
  final Map<String, dynamic> settings;
  final int dayEnds;
  final AdminData d;

  @override
  Widget build(BuildContext context) => _page([
    SectionCard(
      title: 'Cafe information',
      icon: Icons.info_outline_rounded,
      trailing: TextButton.icon(
        onPressed: () => showCafeForm(context, cafe: cafe, currentDayEndsAt: dayEnds, platform: d.settings, plans: d.plans),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      ),
      child: KvList([
        ('Name', cafe.name),
        ('Owner name', cafe.ownerName),
        ('Email', cafe.ownerEmail),
        ('Phone', cafe.contactNumber),
        ('Address', cafe.address),
        ('City', cafe.city),
        ('State', cafe.state),
        ('Country', cafe.country),
        ('GST number', cafe.gstNumber),
        ('Status', cafe.status),
        ('Business day ends', BusinessDay.label(dayEnds)),
        ('Created', fmtDate(cafe.createdAt)),
        ('Last updated', fmtDate(cafe.updatedAt)),
      ]),
    ),
    SectionCard(
      title: 'Receipt settings (set by the cafe)',
      icon: Icons.receipt_long_outlined,
      child: KvList([
        ('Name on bills', (settings['shopName'] ?? '').toString()),
        ('Tagline', (settings['tagline'] ?? '').toString()),
        ('GST on bills', settings['showGst'] == true ? 'Yes · ${settings['gstPercentage'] ?? ''}%' : 'No'),
        ('Tables', (settings['numberOfTables'] ?? '').toString()),
      ]),
    ),
  ]);
}

class _Staff extends StatelessWidget {
  const _Staff({required this.cafe, required this.d});
  final CafeSummary cafe;
  final AdminData d;

  @override
  Widget build(BuildContext context) {
    final list = d.staff.where((s) => s.cafeId == cafe.id).toList();
    return _page([
      SectionCard(
        title: 'Logins',
        subtitle: kLoginHelp,
        icon: Icons.badge_outlined,
        trailing: FilledButton.icon(
          onPressed: () => showAdminCommand(context, title: 'Add a login for ${cafe.name}', why: kLoginHelp, command: loginCommand(cafe.id)),
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
          label: const Text('Add login'),
        ),
        child: list.isEmpty
            ? const InlineEmpty('No login for this cafe yet. Add one to let its staff sign in.', icon: Icons.person_off_outlined)
            : Column(
                children: [for (final s in list) StaffTile(member: s, cafeName: cafe.name)],
              ),
      ),
    ]);
  }
}

/// A login row with its role, status and the on/off command.
class StaffTile extends StatelessWidget {
  const StaffTile({super.key, required this.member, required this.cafeName, this.onOpenCafe});
  final StaffMember member;
  final String cafeName;

  /// When set (staff list across cafes), the cafe name is shown as a link.
  final VoidCallback? onOpenCafe;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = member;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: p.primaryTint,
        child: Icon(Icons.person_outline_rounded, color: p.primary),
      ),
      title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${s.isUsernameLogin ? 'Username: ${s.loginName}' : s.email} · ${s.roleLabel}'),
          if (onOpenCafe != null)
            InkWell(
              onTap: onOpenCafe,
              borderRadius: Radii.controlR,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront_outlined, size: 14, color: p.primary),
                  const SizedBox(width: 4),
                  Flexible(child: Text(cafeName, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.primary, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
        ],
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          StatusChip(s.isActive ? 'Active' : 'Off', color: s.isActive ? p.success : p.inkSubtle, tint: s.isActive ? p.successTint : p.surfaceAlt),
          IconButton(
            tooltip: s.isActive ? 'Turn access off' : 'Turn access on',
            icon: Icon(s.isActive ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 20),
            onPressed: () => showAdminCommand(
              context,
              title: '${s.isActive ? 'Turn off' : 'Turn on'} ${s.loginName}',
              why: s.isActive
                  ? 'The login stops working ($cafeName staff using it are signed out within an hour). No data is deleted.'
                  : 'The login works again with its old password.',
              command: accessCommand(s.loginName, enable: !s.isActive),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSales extends StatelessWidget {
  const _MenuSales({required this.cafeId, required this.dayEnds, this.ops});
  final String cafeId;
  final int dayEnds;
  final Future<CafeOpsSummary>? ops;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FutureBuilder<CafeOpsSummary>(
      future: ops ?? AdminService.instance.cafeOps(cafeId, dayEndsAt: dayEnds),
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(message: friendlyError(snap.error, 'load the summary'));
        if (!snap.hasData) return const LoadingState(label: 'Counting…');
        final o = snap.data!;
        return _page([
          ResponsiveGrid(
            minTileWidth: 190,
            equalHeights: true,
            fill: true,
            children: [
              StatCard(label: 'Categories', value: _n(o.categories), icon: Icons.category_outlined, color: p.info, caption: 'Menu sections'),
              StatCard(
                label: 'Menu items',
                value: _n(o.menuItems),
                icon: Icons.restaurant_menu_outlined,
                color: p.primary,
                caption: o.availableItems == null ? 'Items on the menu' : '${o.availableItems} available',
              ),
              StatCard(
                label: 'Orders today',
                value: _n(o.ordersToday),
                icon: Icons.receipt_long_outlined,
                color: p.success,
                caption: 'Business day (ends ${BusinessDay.label(dayEnds)})',
              ),
              StatCard(
                label: 'Billed, last 30 days',
                value: o.billed30d == null ? '—' : Fmt.money(o.billed30d!.round()),
                icon: Icons.trending_up_rounded,
                color: p.violet,
                caption: o.orders30d == null ? 'Orders: —' : '${o.orders30d} orders',
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          SectionCard(
            title: 'Activity',
            icon: Icons.schedule_rounded,
            child: KvList([('Last order', o.lastOrderAt == null ? 'No orders yet' : Fmt.dateTime(o.lastOrderAt))]),
          ),
          Text('Only counts and totals are read; the Super Admin never downloads a cafe\'s bills.', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
        ]);
      },
    );
  }
}

class _Subscription extends StatelessWidget {
  const _Subscription({required this.cafe, required this.d, required this.now, required this.history});
  final CafeSummary cafe;
  final AdminData d;
  final DateTime now;
  final Stream<List<Map<String, dynamic>>> history;

  @override
  Widget build(BuildContext context) {
    final st = cafe.subState(now);
    return _page([
      SectionCard(
        title: 'Current subscription',
        icon: Icons.workspace_premium_outlined,
        trailing: SubStateChip(st),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!cafe.hasSubscription)
              const InlineEmpty('No plan assigned yet.')
            else
              KvList([
                ('Plan', cafe.planName ?? '—'),
                ('Billing', cafe.billingCycle.isEmpty ? '—' : cafe.billingCycle[0].toUpperCase() + cafe.billingCycle.substring(1)),
                ('Amount', cafe.amount > 0 ? Fmt.money(cafe.amount) : '—'),
                ('Started', fmtDate(cafe.startDate)),
                ('Ends', '${fmtDate(cafe.expiryDate)} · ${daysLeftLabel(cafe.daysLeft(now))}'),
                ('Payment', switch (cafe.paymentStatus) { 'paid' => 'Paid', 'pending' => 'Pending', 'none' || '' => '—', final s => s }),
              ]),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => showAssignPlan(context, cafe, d.plans),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: Text(cafe.hasSubscription ? 'Change plan' : 'Assign plan'),
                ),
                if (cafe.hasSubscription)
                  OutlinedButton.icon(
                    onPressed: () => showRenew(context, cafe),
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    label: const Text('Renew'),
                  ),
                if (cafe.hasSubscription && st.running && st != SubState.cancelled)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
                    onPressed: () => confirmCancelSubscription(context, cafe),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel subscription'),
                  ),
              ],
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'History',
        icon: Icons.history_rounded,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: history,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.data!.isEmpty) return const InlineEmpty('No subscription changes yet');
            return Column(
              children: [
                for (final h in snap.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_historyTitle(h), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        Fmt.dateTime(h['at']),
                        if (h['expiryDate'] != null) 'until ${Fmt.date(h['expiryDate'])}',
                        if (h['amount'] is num && (h['amount'] as num) > 0) Fmt.money(h['amount'] as num),
                      ].join(' · '),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ]);
  }

  static String _historyTitle(Map<String, dynamic> h) {
    final plan = h['planName'] == null ? '' : ' · ${h['planName']}';
    return switch (h['action']) {
      'trial' => 'Trial started$plan',
      'assigned' => 'Plan assigned$plan',
      'changed' => 'Plan changed$plan',
      'renewed' => 'Renewed$plan',
      'cancelled' => 'Cancelled$plan',
      'payment' => 'Payment ${h['receiptNo'] ?? ''} · ${h['method'] ?? ''}',
      _ => (h['action'] ?? '').toString(),
    };
  }
}

class _Payments extends StatelessWidget {
  const _Payments({required this.cafe, required this.d});
  final CafeSummary cafe;
  final AdminData d;

  @override
  Widget build(BuildContext context) {
    final list = d.payments.where((x) => x.cafeId == cafe.id).toList();
    final total = list.where((x) => x.status != 'refunded').fold<double>(0, (t, x) => t + x.amount);
    return _page([
      SectionCard(
        title: 'Payments',
        subtitle: list.isEmpty ? null : '${list.length} recorded · ${Fmt.money(total)} received',
        icon: Icons.payments_outlined,
        trailing: FilledButton.icon(
          onPressed: () => showRecordPayment(context, d.cafes, cafe: cafe),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Record payment'),
        ),
        child: list.isEmpty
            ? const InlineEmpty('No payments recorded for this cafe')
            : Column(
                children: [
                  for (final x in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${x.receiptNo} · ${Fmt.money(x.amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [Fmt.date(x.paidAt), x.method, if (x.planName.isNotEmpty) x.planName, if (x.referenceId.isNotEmpty) 'Ref ${x.referenceId}'].join(' · '),
                      ),
                    ),
                ],
              ),
      ),
    ]);
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.stream});
  final Stream<List<Map<String, dynamic>>> stream;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snap) {
      if (snap.hasError) return ErrorState(message: friendlyError(snap.error, 'load the activity'));
      if (!snap.hasData) return const LoadingState();
      return _page([
        SectionCard(
          title: 'Activity',
          icon: Icons.history_rounded,
          child: snap.data!.isEmpty
              ? const InlineEmpty('No activity recorded for this cafe')
              : Column(children: [for (final e in snap.data!) AuditTile(entry: e)]),
        ),
      ]);
    },
  );
}

/// One audit-log entry.
class AuditTile extends StatelessWidget {
  const AuditTile({super.key, required this.entry, this.cafeName});
  final Map<String, dynamic> entry;
  final String? cafeName;

  @override
  Widget build(BuildContext context) {
    final details = entry['details'] is Map ? Map<String, dynamic>.from(entry['details'] as Map) : const <String, dynamic>{};
    final detailText = details.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
        .join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text([auditLabel((entry['action'] ?? '').toString()), ?cafeName].join(' · '), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [Fmt.dateTime(entry['at']), (entry['actorRole'] ?? '').toString(), if (detailText.isNotEmpty) detailText].where((s) => s.isNotEmpty).join(' · '),
      ),
    );
  }
}

String _n(int? v) => v == null ? '—' : '$v';
