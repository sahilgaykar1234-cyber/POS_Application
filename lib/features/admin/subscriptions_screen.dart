import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/confirm_dialog.dart';
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
              if (_tab == 1 && d.plans.isNotEmpty && missingRecommendedPlans(d.plans).isNotEmpty)
                OutlinedButton.icon(onPressed: () => _addRecommended(context, d), icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text('Add recommended plans')),
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
          message: 'Start with the recommended plans for this POS (Free Trial, Basic ₹499, Standard ₹899, Premium ₹1,499 per month) '
              'and edit the prices any time, or create your own.',
          action: Wrap(spacing: Space.sm, runSpacing: Space.sm, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              key: const Key('add-recommended'),
              onPressed: () => _addRecommended(context, d),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Add recommended plans'),
            ),
            OutlinedButton.icon(onPressed: () => showPlanForm(context), icon: const Icon(Icons.add), label: const Text('New plan')),
          ]),
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
                const SizedBox(height: Space.sm),
                Divider(height: 1, color: p.border),
                const SizedBox(height: Space.xs),
                Row(children: [
                  TextButton.icon(
                    key: Key('plan-edit-${plan.id}'),
                    onPressed: () => showPlanForm(context, plan: plan),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    key: Key('plan-visibility-${plan.id}'),
                    onPressed: () => _toggleVisible(context, plan),
                    icon: Icon(plan.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    label: Text(plan.isActive ? 'Hide' : 'Show'),
                  ),
                  const Spacer(),
                  IconButton(
                    key: Key('plan-delete-${plan.id}'),
                    tooltip: 'Delete plan',
                    onPressed: () => _deletePlan(context, plan, d.cafes.where((c) => c.planId == plan.id && !c.isDeleted).length),
                    icon: Icon(Icons.delete_outline, color: p.danger),
                  ),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }
}

Future<void> _addRecommended(BuildContext context, AdminData d) async {
  try {
    final n = await AdminService.instance.addRecommendedPlans(d.plans);
    if (context.mounted) showSuccess(context, n == 0 ? 'All recommended plans already exist' : '$n plans added. Tap a plan to edit its price.');
  } catch (e) {
    if (context.mounted) showError(context, 'Could not add plans: $e');
  }
}

Future<void> _toggleVisible(BuildContext context, SubscriptionPlan plan) async {
  try {
    await AdminService.instance.savePlan(plan.id, {'name': plan.name, 'isActive': !plan.isActive});
    if (context.mounted) showSuccess(context, plan.isActive ? '${plan.name} hidden from new subscriptions' : '${plan.name} is available again');
  } catch (e) {
    if (context.mounted) showError(context, 'Could not update: $e');
  }
}

Future<void> _deletePlan(BuildContext context, SubscriptionPlan plan, int usedBy) async {
  final ok = await showDangerConfirmDialog(
    context,
    title: 'Delete plan "${plan.name}"?',
    message: usedBy == 0
        ? 'No cafe uses this plan. This cannot be undone.'
        : '$usedBy cafe${usedBy == 1 ? '' : 's'} use this plan. Their current subscription stays as it is (name, price and end date are saved with the cafe), '
            'but the plan can no longer be assigned. Tip: "Hide" keeps it for existing cafes instead.',
    confirmLabel: 'Delete plan',
  );
  if (!ok || !context.mounted) return;
  try {
    await AdminService.instance.deletePlan(plan, usedBy: usedBy);
    if (context.mounted) showSuccess(context, 'Plan ${plan.name} deleted');
  } catch (e) {
    if (context.mounted) showError(context, 'Could not delete: $e');
  }
}
