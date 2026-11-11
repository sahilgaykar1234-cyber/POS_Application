import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/app_user.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/services/staff_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../auth/login_screen.dart';

/// Staff list for one cafe. Used by:
///  - Super Admin: can add/manage Managers and Captains.
///  - Manager:     can add/manage Captains of their own cafe.
/// Every action is re-authorised by Cloud Functions on the server.
class StaffManagementScreen extends StatelessWidget {
  const StaffManagementScreen({super.key, required this.cafeId, required this.cafeName, this.embedded = false});

  final String cafeId;
  final String cafeName;

  /// Inside another screen's tab (no own app bar).
  final bool embedded;

  AppUser? get _me => AuthService.instance.currentUser;

  /// Roles the current user may create (mirrors functions/src/permissions.js).
  List<UserRole> get _invitableRoles {
    final me = _me;
    if (me == null) return const [];
    if (me.isSuperAdmin) return const [UserRole.manager, UserRole.captain];
    if (me.isManager && me.cafeId == cafeId) return const [UserRole.captain];
    return const [];
  }

  bool _canManage(StaffMember m) {
    final me = _me;
    if (me == null || m.uid == me.uid) return false;
    return _invitableRoles.contains(m.role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: embedded ? null : AppBar(title: Text('Staff · $cafeName')),
      floatingActionButton: _invitableRoles.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-staff',
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add staff'),
              onPressed: () => _showInviteDialog(context),
            ),
      body: StreamBuilder<List<StaffMember>>(
        stream: StaffService.instance.watchCafeStaff(cafeId),
        builder: (context, snap) {
          if (snap.hasError) return const ErrorState(message: 'Could not load staff.');
          if (!snap.hasData) return const LoadingState();
          final staff = snap.data!;
          return PageBody(
            maxWidth: 900,
            children: [
              PageHeader(
                title: 'Staff',
                subtitle: '${staff.length} account${staff.length == 1 ? '' : 's'} · each person signs in with their own login',
              ),
              if (staff.isEmpty)
                const EmptyState(icon: Icons.group_outlined, title: 'No staff yet', message: 'Tap "Add staff" to invite someone.')
              else
                for (final m in staff) _StaffTile(member: m, canManage: _canManage(m)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context) async {
    final link = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteDialog(cafeId: cafeId, roles: _invitableRoles),
    );
    if (link != null && context.mounted) {
      await showLinkDialog(
        context,
        title: 'Invitation sent',
        message: 'We emailed a "set your password" link. You can also copy it and send it on WhatsApp. '
            'The link works once and expires after a while.',
        link: link,
      );
    }
  }
}

class _StaffTile extends StatefulWidget {
  const _StaffTile({required this.member, required this.canManage});
  final StaffMember member;
  final bool canManage;

  @override
  State<_StaffTile> createState() => _StaffTileState();
}

class _StaffTileState extends State<_StaffTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthService.friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() => _run(() async {
        final link = await StaffService.instance.sendPasswordReset(widget.member);
        if (!mounted) return;
        await showLinkDialog(
          context,
          title: 'Reset link sent',
          message: 'A password reset email was sent to ${widget.member.email}. '
              'You can also share this link directly.',
          link: link,
        );
      });

  Future<void> _toggleActive() async {
    final m = widget.member;
    final disabling = !m.isDisabled;
    if (disabling) {
      final ok = await showDangerConfirmDialog(
        context,
        title: 'Disable ${m.displayName}?',
        message: '${m.displayName} will be signed out and will not be able to log in until enabled again. '
            'No data will be deleted.',
        confirmLabel: 'Disable',
      );
      if (!ok) return;
    }
    await _run(() async {
      await StaffService.instance.setActive(m, !disabling);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(disabling ? '${m.displayName} disabled' : '${m.displayName} enabled'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final p = context.palette;
    final statusLabel = switch (m.status) {
      'invited' => 'Invited',
      'disabled' => 'Disabled',
      _ => 'Active',
    };

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: ListTile(
        minTileHeight: 64,
        leading: CircleAvatar(
          backgroundColor: p.primaryTint,
          child: Icon(m.role == UserRole.manager ? Icons.badge_outlined : Icons.restaurant_outlined, color: p.primary),
        ),
        title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${m.role?.label ?? 'Unknown role'} · ${AppConfig.displayLogin(m.email)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(statusLabel),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (widget.canManage)
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (v) => v == 'reset' ? _resetPassword() : _toggleActive(),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'reset', child: Text('Send password reset')),
                  PopupMenuItem(value: 'toggle', child: Text(m.isDisabled ? 'Enable account' : 'Disable account')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.cafeId, required this.roles});
  final String cafeId;
  final List<UserRole> roles;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  late UserRole _role = widget.roles.last; // captain by default
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final link = await StaffService.instance.invite(
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        role: _role,
        cafeId: widget.cafeId,
      );
      if (mounted) Navigator.pop(context, link);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff member'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                enabled: !_loading,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.length < 2) return 'Please enter a name';
                  if (s.length > 80) return 'Name is too long';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                validator: LoginValidators.email,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: [
                  for (final r in widget.roles) DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: _loading ? null : (r) => setState(() => _role = r ?? _role),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: context.palette.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send invite'),
        ),
      ],
    );
  }
}

/// Shows a one-time setup/reset link with a copy button.
Future<void> showLinkDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String link,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: ctx.palette.success),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: ctx.palette.inkMuted)),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ctx.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(link, maxLines: 3, style: TextStyle(fontSize: 12, color: ctx.palette.inkSubtle)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (link.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy link'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Link copied')));
              }
            },
          ),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
      ],
    ),
  );
}
