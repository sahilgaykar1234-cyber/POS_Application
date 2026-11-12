import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_dialogs.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';

/// Pure filter for the staff list (unit-tested).
List<StaffMember> filterStaff(List<StaffMember> staff, AdminData d, {String search = '', String? cafeId, String role = 'all', String status = 'all'}) {
  final q = search.trim().toLowerCase();
  return staff.where((s) {
    if (s.role == 'superAdmin') return false;
    if (cafeId != null && s.cafeId != cafeId) return false;
    if (role != 'all' && s.role != role) return false;
    if (status == 'active' && !s.isActive) return false;
    if (status == 'off' && s.isActive) return false;
    if (q.isEmpty) return true;
    return s.displayName.toLowerCase().contains(q) || s.email.toLowerCase().contains(q) || d.cafeName(s.cafeId).toLowerCase().contains(q);
  }).toList();
}

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  String _q = '';
  String? _cafe;
  String _role = 'all';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.staff.isEmpty) return const LoadingState(label: 'Loading staff…');
        final list = filterStaff(d.staff, d, search: _q, cafeId: _cafe, role: _role, status: _status);
        final all = d.staff.where((s) => s.role != 'superAdmin');
        final p = context.palette;
        return PageBody(
          children: [
            PageHeader(
              title: 'Staff',
              subtitle:
                  '${all.length} logins · ${all.where((s) => s.role == 'manager').length} manager · ${all.where((s) => s.role == 'captain').length} captain',
            ),
            Container(
              padding: const EdgeInsets.all(Space.md),
              margin: const EdgeInsets.only(bottom: Space.lg),
              decoration: BoxDecoration(color: p.infoTint, borderRadius: Radii.cardR),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: p.info, size: 20),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'Shared cafe logins choose Manager or Captain view after signing in. Passwords are never shown or stored here. '
                      '$kLoginHelp',
                      style: TextStyle(color: p.ink, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 700;
                final w = narrow ? (c.maxWidth - Space.sm) / 2 : 180.0;
                return Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    SearchField(width: narrow ? double.infinity : 300, hint: 'Name, login or cafe', onChanged: (v) => setState(() => _q = v)),
                    SizedBox(
                      width: w,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _cafe,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All cafes')),
                          for (final x in d.cafes.where((c) => !c.isDeleted))
                            DropdownMenuItem(
                              value: x.id,
                              child: Text(x.name, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _cafe = v),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: DropdownButtonFormField<String>(
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All roles')),
                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                          DropdownMenuItem(value: 'captain', child: Text('Captain')),
                        ],
                        onChanged: (v) => setState(() => _role = v ?? 'all'),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Any status')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'off', child: Text('Turned off')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'all'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.lg),
            SurfaceCard(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.badge_outlined, title: 'No logins found', message: 'Add a login from a cafe\'s page.')
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: p.border),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: StaffTile(
                                    member: list[i],
                                    cafeName: d.cafeName(list[i].cafeId),
                                    onOpenCafe: list[i].cafeId == null ? null : () => openCafe(context, list[i].cafeId!, widget.data),
                                  ),
                                ),
                              ],
                            ),
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
