import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';
import 'cafe_form_screen.dart';

class CafesTab extends StatefulWidget {
  const CafesTab({super.key});

  @override
  State<CafesTab> createState() => _CafesTabState();
}

class _CafesTabState extends State<CafesTab> {
  final _stream = AdminService.instance.watchCafes();
  String _query = '';
  String _filter = 'all'; // all | active | blocked | attention | deleted

  bool _matches(CafeSummary c, DateTime now) {
    final q = _query;
    if (q.isNotEmpty &&
        !c.name.toLowerCase().contains(q) &&
        !c.ownerName.toLowerCase().contains(q) &&
        !c.contactNumber.contains(q) &&
        !c.id.toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      'active' => !c.isDeleted && c.access(now).canUsePos,
      'blocked' => !c.isDeleted && !c.access(now).canUsePos,
      'attention' => c.isOverdue(now) || c.isPaymentPending(now),
      'deleted' => c.isDeleted,
      _ => !c.isDeleted,
    };
  }

  Future<void> _create() async {
    await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CafeFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-cafe',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business),
        label: const Text('New cafe', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _create,
      ),
      body: StreamBuilder<List<CafeSummary>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return const EmptyState(icon: Icons.error_outline, title: 'Could not load cafes');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          final now = DateTime.now();
          final cafes = snap.data!.where((c) => _matches(c, now)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by cafe, owner, phone or ID',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final f in const [
                    ('all', 'All'),
                    ('active', 'Running'),
                    ('blocked', 'Blocked'),
                    ('attention', 'Payment due'),
                    ('deleted', 'Deleted'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (cafes.isEmpty)
                EmptyState(
                  icon: Icons.storefront_outlined,
                  title: snap.data!.isEmpty ? 'No cafes yet' : 'No cafes match',
                  message: snap.data!.isEmpty ? 'Tap "New cafe" to onboard your first customer.' : null,
                )
              else
                for (final c in cafes) _CafeCard(cafe: c, now: now),
            ],
          );
        },
      ),
    );
  }
}

class _CafeCard extends StatelessWidget {
  const _CafeCard({required this.cafe, required this.now});
  final CafeSummary cafe;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final access = cafe.access(now);
    final subLine = [
      if (cafe.planName != null) cafe.planName!,
      if (cafe.subscriptionStatus != '—') cafe.subscriptionStatus,
      if (cafe.expiryDate != null) 'until ${Fmt.date(cafe.expiryDate)}',
    ].join(' · ');

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceAlt,
          child: Text(cafe.name.isEmpty ? '?' : cafe.name[0].toUpperCase(),
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
        ),
        title: Text(cafe.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cafe.ownerName.isNotEmpty || cafe.contactNumber.isNotEmpty)
              Text([cafe.ownerName, cafe.contactNumber].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text(subLine.isEmpty ? 'No subscription set' : subLine, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            if (cafe.legacyData)
              const Text('Data migration pending', style: TextStyle(color: AppColors.accent, fontSize: 12)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(cafe.status),
            if (!cafe.isDeleted && !access.canUsePos) ...[
              const SizedBox(height: 4),
              const StatusChip('POS blocked', color: AppColors.danger),
            ],
          ],
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CafeDetailScreen(cafeId: cafe.id))),
      ),
    );
  }
}
