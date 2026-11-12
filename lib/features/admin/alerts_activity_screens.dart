import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import 'admin_dashboard_screen.dart';
import 'admin_data.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';
import '../../core/utils/friendly_error.dart';

/// What needs attention now, worked out from live data.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertLevel? _level;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.cafes.isEmpty) return const LoadingState();
        final all = computeAlerts(cafes: d.cafes, staff: d.staff, now: DateTime.now(), settings: d.settings);
        final list = all.where((a) => _level == null || a.level == _level).toList();
        final p = context.palette;
        int n(AlertLevel l) => all.where((a) => a.level == l).length;
        return PageBody(
          children: [
            PageHeader(title: 'Alerts', subtitle: 'Expiring and expired plans, pending payments, cafes without a login, new cafes. Updated live.'),
            FilterPills<AlertLevel?>(
              options: [
                (null, 'All (${all.length})'),
                (AlertLevel.critical, 'Critical (${n(AlertLevel.critical)})'),
                (AlertLevel.warning, 'Warnings (${n(AlertLevel.warning)})'),
                (AlertLevel.info, 'Info (${n(AlertLevel.info)})'),
              ],
              selected: _level,
              onSelected: (v) => setState(() => _level = v),
            ),
            const SizedBox(height: Space.md),
            SurfaceCard(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.task_alt_rounded, title: 'Nothing needs attention')
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: p.border),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                            child: AlertTile(alert: list[i], data: widget.data),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Every Super Admin / staff action that was logged (no secrets are stored).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.data, this.stream});
  final ValueListenable<AdminData> data;
  final Stream<List<Map<String, dynamic>>>? stream;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final _stream = widget.stream ?? AdminService.instance.watchAuditLogs(limit: 500);
  String _kind = 'all';
  String? _cafe;

  static const kinds = {
    'all': 'All activity',
    'cafe': 'Cafes',
    'subscription': 'Subscriptions',
    'payment': 'Payments',
    'plan': 'Plans',
    'staff': 'Staff',
    'platform': 'Settings',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(message: friendlyError(snap.error, 'load the activity'));
          if (!snap.hasData) return const LoadingState(label: 'Loading activity…');
          final p = context.palette;
          final list = snap.data!.where((e) {
            final a = (e['action'] ?? '').toString();
            if (_kind != 'all' && !a.startsWith('$_kind.')) return false;
            if (_cafe != null && e['cafeId'] != _cafe) return false;
            return true;
          }).toList();
          return PageBody(
            children: [
              const PageHeader(title: 'Activity log', subtitle: 'Who changed what, and when. Entries can\'t be edited or deleted.'),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [for (final e in kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _kind = v ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _cafe,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All cafes')),
                        for (final c in d.cafes)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _cafe = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              SurfaceCard(
                child: list.isEmpty
                    ? const EmptyState(icon: Icons.history_rounded, title: 'No activity')
                    : Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: p.border),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                              child: AuditTile(entry: list[i], cafeName: list[i]['cafeId'] == null ? null : d.cafeName(list[i]['cafeId'].toString())),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
