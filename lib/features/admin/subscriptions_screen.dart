import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_dialogs.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import 'cafe_detail_screen.dart';

/// Every cafe's plan and period, plus the plans themselves.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  int _tab = 0;
  SubState? _filter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.cafes.isEmpty) return const LoadingState();
        final now = DateTime.now();
        final p = context.palette;
        final cafes = d.cafes.where((c) => !c.isDeleted && (_filter == null || c.subState(now) == _filter)).toList()
          ..sort((a, b) => (a.expiryDate ?? DateTime(9999)).compareTo(b.expiryDate ?? DateTime(9999)));
        return PageBody(children: [
          PageHeader(
            title: 'Subscriptions',
            subtitle: 'Plans, trials and renewals. No payment gateway: money is recorded when received.',
            actions: [
              if (_tab == 1) FilledButton.icon(key: const Key('new-plan'), onPressed: () => showPlanForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('New plan')),
            ],
          ),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('Cafes (${d.cafes.where((c) => !c.isDeleted).length})'), icon: const Icon(Icons.storefront_outlined, size: 18)),
              ButtonSegment(value: 1, label: Text('Plans (${d.plans.length})'), icon: const Icon(Icons.workspace_premium_outlined, size: 18)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: Space.lg),
          if (_tab == 0) ...[
            FilterPills<SubState?>(
              options: [(null, 'All'), for (final s in SubState.values) (s, '${s.label} (${d.cafes.where((c) => !c.isDeleted && c.subState(now) == s).length})')],
              selected: _filter,
              onSelected: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: Space.md),
            SurfaceCard(
              child: cafes.isEmpty
                  ? const EmptyState(icon: Icons.workspace_premium_outlined, title: 'Nothing here')
                  : Column(children: [
                      for (var i = 0; i < cafes.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.border),
                        _SubRow(cafe: cafes[i], d: d, data: widget.data, now: now),
                      ],
                    ]),
            ),
          ] else
            _Plans(d: d),
        ]);
      },
    );
  }
}

class _SubRow extends StatelessWidget {
  const _SubRow({required this.cafe, required this.d, required this.data, required this.now});
  final CafeSummary cafe;
  final AdminData d;
  final ValueListenable<AdminData> data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final st = cafe.subState(now);
    return InkWell(
      onTap: () => openCafe(context, cafe.id, data),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cafe.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                cafe.hasSubscription
                    ? [cafe.planName ?? 'Plan', if (cafe.amount > 0) '${Fmt.money(cafe.amount)}/${cafe.billingCycle == 'yearly' ? 'yr' : 'mo'}', 'ends ${fmtDate(cafe.expiryDate)} (${daysLeftLabel(cafe.daysLeft(now))})'].join(' · ')
                    : 'No plan assigned',
                style: TextStyle(color: p.inkSubtle, fontSize: 12.5),
              ),
            ]),
          ),
          SubStateChip(st),
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (v) => switch (v) {
              'assign' => showAssignPlan(context, cafe, d.plans),
              'renew' => showRenew(context, cafe),
              'pay' => showRecordPayment(context, d.cafes, cafe: cafe),
              'cancel' => confirmCancelSubscription(context, cafe),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'assign', child: Text(cafe.hasSubscription ? 'Change plan' : 'Assign plan')),
              if (cafe.hasSubscription) const PopupMenuItem(value: 'renew', child: Text('Renew')),
              const PopupMenuItem(value: 'pay', child: Text('Record payment')),
              if (cafe.hasSubscription && st.running && st != SubState.cancelled) const PopupMenuItem(value: 'cancel', child: Text('Cancel subscription')),
            ],
          ),
        ]),
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  const _Plans({required this.d});
  final AdminData d;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (d.plans.isEmpty) {
      return SurfaceCard(
        child: EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: 'No plans yet',
          message: 'Create plans like Free Trial, Basic, Standard and Premium with your own prices.',
          action: FilledButton.icon(onPressed: () => showPlanForm(context), icon: const Icon(Icons.add), label: const Text('New plan')),
        ),
      );
    }
    final now = DateTime.now();
    return ResponsiveGrid(minTileWidth: 260, maxColumns: 4, equalHeights: true, children: [
      for (final plan in d.plans)
        SurfaceCard(
          child: InkWell(
            onTap: () => showPlanForm(context, plan: plan),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(plan.name, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  StatusChip(plan.isActive ? plan.tier.label : 'Hidden', color: plan.isActive ? p.info : p.inkSubtle, tint: plan.isActive ? p.infoTint : p.surfaceAlt),
                ]),
                const SizedBox(height: Space.xs),
                Text(plan.priceLabel, style: TextStyle(fontWeight: FontWeight.w700, color: p.primary)),
                if (plan.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(plan.description, style: TextStyle(color: p.inkSubtle, fontSize: 13))),
                const SizedBox(height: Space.sm),
                Text(
                  [
                    plan.maxStaff == null ? 'Unlimited staff' : 'Up to ${plan.maxStaff} staff',
                    if (plan.maxDevices != null) '${plan.maxDevices} devices',
                  ].join(' · '),
                  style: TextStyle(color: p.inkMuted, fontSize: 13),
                ),
                for (final f in plan.features.take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [Icon(Icons.check_rounded, size: 16, color: p.success), const SizedBox(width: 6), Expanded(child: Text(f, style: const TextStyle(fontSize: 13)))]),
                  ),
                const Spacer(),
                const SizedBox(height: Space.sm),
                Text('${d.cafes.where((c) => c.planId == plan.id && c.subState(now).running).length} cafes on this plan', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
              ]),
            ),
          ),
        ),
    ]);
  }
}
