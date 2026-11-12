import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/subscription/cafe_access.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_dialogs.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import 'cafe_detail_screen.dart';

enum CafeSort { name, newest, expiry }

/// Pure filter for the cafes list (unit-tested).
List<CafeSummary> filterCafes(
  List<CafeSummary> cafes, {
  String search = '',
  String status = 'all',
  SubState? sub,
  CafeSort sort = CafeSort.name,
  required DateTime now,
}) {
  final q = search.trim().toLowerCase();
  final out = cafes.where((c) {
    if (c.isDeleted && status != CafeStatus.deleted) return false;
    if (status != 'all' && c.status != status) return false;
    if (sub != null && c.subState(now) != sub) return false;
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        c.ownerName.toLowerCase().contains(q) ||
        c.city.toLowerCase().contains(q) ||
        c.contactNumber.contains(q) ||
        c.id.toLowerCase() == q;
  }).toList();
  out.sort((a, b) => switch (sort) {
        CafeSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        CafeSort.newest => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
        CafeSort.expiry => (a.expiryDate ?? DateTime(9999)).compareTo(b.expiryDate ?? DateTime(9999)),
      });
  return out;
}

class CafesScreen extends StatefulWidget {
  const CafesScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<CafesScreen> createState() => _CafesScreenState();
}

class _CafesScreenState extends State<CafesScreen> {
  String _q = '';
  String _status = 'all';
  SubState? _sub;
  CafeSort _sort = CafeSort.name;

  Future<void> _create(AdminData d) async {
    final id = await showCafeForm(context, platform: d.settings, plans: d.plans);
    if (id == null || !mounted) return;
    final name = widget.data.value.cafeName(id);
    await showNewCafeLoginHelp(context, id, name == 'Unknown cafe' ? 'The cafe' : name);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.cafes.isEmpty) return const LoadingState(label: 'Loading cafes…');
        final now = DateTime.now();
        final list = filterCafes(d.cafes, search: _q, status: _status, sub: _sub, sort: _sort, now: now);
        return PageBody(children: [
          PageHeader(
            title: 'Cafes',
            subtitle: '${d.cafes.where((c) => !c.isDeleted).length} cafes · ${d.cafes.where((c) => c.isActive).length} active',
            actions: [FilledButton.icon(key: const Key('new-cafe'), onPressed: () => _create(d), icon: const Icon(Icons.add_business_outlined, size: 18), label: const Text('New cafe'))],
          ),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 700;
            final w = narrow ? (c.maxWidth - Space.sm) / 2 : 180.0;
            return Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SearchField(width: narrow ? double.infinity : 300, hint: 'Name, owner, city or phone', onChanged: (v) => setState(() => _q = v)),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All statuses')),
                    for (final s in [CafeStatus.active, CafeStatus.inactive, CafeStatus.suspended]) DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
              ),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<SubState?>(
                  initialValue: _sub,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any plan')),
                    for (final s in SubState.values) DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(() => _sub = v),
                ),
              ),
              SizedBox(
                width: w,
                child: DropdownButtonFormField<CafeSort>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.sort_rounded, size: 18)),
                  items: const [
                    DropdownMenuItem(value: CafeSort.name, child: Text('Name')),
                    DropdownMenuItem(value: CafeSort.newest, child: Text('Newest')),
                    DropdownMenuItem(value: CafeSort.expiry, child: Text('Ending soonest')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? _sort),
                ),
              ),
            ]);
          }),
          const SizedBox(height: Space.lg),
          if (list.isEmpty)
            SurfaceCard(
              child: EmptyState(
                icon: Icons.storefront_outlined,
                title: d.cafes.isEmpty ? 'No cafes yet' : 'No cafe matches',
                message: d.cafes.isEmpty ? 'Create the first cafe to get started.' : 'Try another search or filter.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 980 ? _Table(cafes: list, d: d, data: widget.data, now: now) : Column(children: [for (final x in list) _Card(cafe: x, d: d, data: widget.data, now: now)]),
            ),
        ]);
      },
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.cafes, required this.d, required this.data, required this.now});
  final List<CafeSummary> cafes;
  final AdminData d;
  final ValueListenable<AdminData> data;
  final DateTime now;

  static const _flex = [24, 12, 16, 14, 14, 8];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4);
    Widget cell(int i, Widget w) => Expanded(flex: _flex[i], child: Align(alignment: Alignment.centerLeft, child: w));
    return SurfaceCard(
      child: Column(children: [
        Container(
          color: p.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(children: [
            cell(0, Text('CAFE', style: head)),
            cell(1, Text('STATUS', style: head)),
            cell(2, Text('PLAN', style: head)),
            cell(3, Text('ENDS', style: head)),
            cell(4, Text('JOINED', style: head)),
            cell(5, Text('LOGINS', style: head)),
            const SizedBox(width: 40),
          ]),
        ),
        for (var i = 0; i < cafes.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.border),
          InkWell(
            key: Key('cafe-row-${cafes[i].id}'),
            onTap: () => openCafe(context, cafes[i].id, data),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              child: Row(children: [
                cell(0, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cafes[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text([cafes[i].ownerName, cafes[i].city].where((s) => s.isNotEmpty).join(' · ').ifEmpty(cafes[i].contactNumber), style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                ])),
                cell(1, CafeStatusChip(cafes[i].status)),
                cell(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SubStateChip(cafes[i].subState(now)),
                  if (cafes[i].planName != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(cafes[i].planName!, style: TextStyle(color: p.inkSubtle, fontSize: 12))),
                ])),
                cell(3, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDate(cafes[i].expiryDate)),
                  if (cafes[i].expiryDate != null) Text(daysLeftLabel(cafes[i].daysLeft(now)), style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                ])),
                cell(4, Text(fmtDate(cafes[i].createdAt))),
                cell(5, Text('${d.staff.where((s) => s.cafeId == cafes[i].id && s.isActive).length}')),
                const SizedBox(width: 40, child: Icon(Icons.chevron_right_rounded)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.cafe, required this.d, required this.data, required this.now});
  final CafeSummary cafe;
  final AdminData d;
  final ValueListenable<AdminData> data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: InkWell(
        key: Key('cafe-card-${cafe.id}'),
        onTap: () => openCafe(context, cafe.id, data),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(cafe.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              CafeStatusChip(cafe.status),
            ]),
            const SizedBox(height: 4),
            Text(
              [cafe.ownerName, cafe.city, 'Joined ${fmtDate(cafe.createdAt)}'].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(color: p.inkSubtle, fontSize: 12),
            ),
            const SizedBox(height: Space.sm),
            Row(children: [
              SubStateChip(cafe.subState(now)),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  [if (cafe.planName != null) cafe.planName!, if (cafe.expiryDate != null) 'ends ${Fmt.date(cafe.expiryDate)}'].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.inkMuted, fontSize: 12),
                ),
              ),
              Text('${d.staff.where((s) => s.cafeId == cafe.id && s.isActive).length} login', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
