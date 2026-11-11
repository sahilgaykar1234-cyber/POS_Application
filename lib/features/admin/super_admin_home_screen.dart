import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/theme/app_theme.dart';
import '../staff/staff_management_screen.dart';

/// Master Admin home. Lists all cafes; tap a cafe to manage its staff.
/// The full dashboard, cafe creation and subscriptions come in later phases.
class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('${AppConfig.appName} · Master Admin',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text(user.email, style: const TextStyle(color: Colors.white54, fontSize: 12))),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutToLogin(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestorePaths.cafes().snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load cafes.', style: TextStyle(color: Colors.white60)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final cafes = snap.data!.docs
              .where((d) => d.data()['status'] != 'deleted')
              .toList()
            ..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));

          if (cafes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No cafes yet.\nCreate the first one with the admin script:\n'
                  'node admin.js create-cafe "<name>"',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Cafes (${cafes.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              for (final doc in cafes) _CafeTile(doc: doc),
            ],
          );
        },
      ),
    );
  }
}

class _CafeTile extends StatelessWidget {
  const _CafeTile({required this.doc});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name = (d['name'] ?? 'Unnamed cafe').toString();
    final status = (d['status'] ?? 'active').toString();
    final active = status == 'active' || status == 'trial';

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceAlt,
          child: Icon(Icons.storefront_rounded, color: AppColors.accent),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('ID: ${doc.id}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11)),
              backgroundColor: (active ? AppColors.success : AppColors.danger).withValues(alpha: 0.18),
              side: BorderSide.none,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StaffManagementScreen(cafeId: doc.id, cafeName: name)),
        ),
      ),
    );
  }
}
