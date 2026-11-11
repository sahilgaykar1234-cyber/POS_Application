import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart' show describeAudit;

/// Audit log of important administrative actions across the platform.
class ActivityTab extends StatelessWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CafeSummary>>(
      stream: AdminService.instance.watchCafes(),
      builder: (context, cafeSnap) {
        final names = {for (final c in cafeSnap.data ?? const <CafeSummary>[]) c.id: c.name};
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: AdminService.instance.watchAuditLogs(limit: 200),
          builder: (context, snap) {
            if (snap.hasError) return const EmptyState(icon: Icons.error_outline, title: 'Could not load activity');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            final logs = snap.data!;
            if (logs.isEmpty) return const EmptyState(icon: Icons.history, title: 'No activity yet');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final l = logs[i];
                final cafe = names[l['cafeId']];
                final actor = (l['actorRole'] ?? (l['actorUid'] == 'system' ? 'system' : l['actorUid'] ?? '')).toString();
                return ListTile(
                  leading: Icon(_icon(l['action']?.toString() ?? ''), color: AppColors.accent),
                  title: Text(describeAudit(l)),
                  subtitle: Text(
                    [?cafe, 'by $actor', Fmt.dateTime(l['at'])].join(' · '),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  IconData _icon(String a) {
    if (a.startsWith('staff')) return Icons.person_outline;
    if (a.startsWith('payment')) return Icons.payments_outlined;
    if (a.startsWith('subscription') || a.startsWith('plan')) return Icons.workspace_premium_outlined;
    if (a.startsWith('migration')) return Icons.move_down;
    return Icons.storefront_outlined;
  }
}
