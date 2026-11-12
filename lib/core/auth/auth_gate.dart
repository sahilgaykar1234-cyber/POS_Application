import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/admin/super_admin_shell.dart';
import '../../features/auth/login_screen.dart';
import '../../features/shell/role_shells.dart';
import '../data/firestore_paths.dart';
import '../subscription/cafe_access.dart';
import '../theme/tokens.dart';
import '../widgets/message_screen.dart';
import 'app_user.dart';
import 'auth_service.dart';

/// Signs out from anywhere: closes any open sub-screens first, then signs out
/// so [AuthGate] (the root route) shows the login screen.
Future<void> signOutToLogin(BuildContext context) async {
  Navigator.of(context).popUntil((route) => route.isFirst);
  await AuthService.instance.signOut();
}

/// Root of the app. Decides what to show from the signed-in user's
/// server-assigned role and cafe — never from anything the user can edit.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return MessageScreen.loading();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        // Keyed by uid so switching accounts always reloads claims.
        return _SignedInGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _SignedInGate extends StatefulWidget {
  const _SignedInGate({super.key, required this.user});
  final User user;

  @override
  State<_SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<_SignedInGate> {
  late Future<AppUser> _appUser;

  @override
  void initState() {
    super.initState();
    _appUser = AuthService.instance.loadAppUser(widget.user);
  }

  void _retry() => setState(() => _appUser = AuthService.instance.loadAppUser(widget.user));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser>(
      future: _appUser,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return MessageScreen.loading('Checking your account…');
        }
        if (snap.hasError) {
          return MessageScreen(
            icon: Icons.wifi_off_rounded,
            title: 'Could not load your account',
            message: 'Please check your internet connection and try again.',
            actionLabel: 'Retry',
            onAction: _retry,
          );
        }

        final appUser = snap.data!;
        if (appUser.loginDisabled) {
          return const _SignOutMessage(
            icon: Icons.lock_outline_rounded,
            title: 'This login is turned off',
            message: 'Please contact the administrator to turn it on again. Your cafe\'s data is safe.',
          );
        }
        if (!appUser.hasValidAssignment) {
          return _SignOutMessage(
            icon: Icons.manage_accounts_outlined,
            title: 'Account not set up',
            message:
                'Your account (${appUser.email}) has no role assigned yet. '
                'Please ask your manager or the administrator to set it up.',
          );
        }

        if (appUser.isSuperAdmin) return const SuperAdminShell();
        return _CafeGate(user: appUser);
      },
    );
  }
}

/// For Manager/Captain: checks the cafe exists and is allowed to operate.
class _CafeGate extends StatelessWidget {
  const _CafeGate({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    // A login turned off by the Super Admin stops right away (the rules
    // already refuse its reads/writes; this explains why).
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.users().doc(user.uid).snapshots(),
      builder: (context, me) {
        if (me.data?.data()?['status'] == 'disabled') {
          return const _SignOutMessage(
            icon: Icons.lock_outline_rounded,
            title: 'This login is turned off',
            message: 'Please contact the administrator to turn it on again. Your cafe\'s data is safe.',
          );
        }
        return _cafe(context);
      },
    );
  }

  Widget _cafe(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.cafe(user.cafeId!).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _SignOutMessage(
            icon: Icons.error_outline,
            title: 'Could not load your cafe',
            message: 'Please check your internet connection, then sign in again.',
          );
        }
        if (!snap.hasData) return MessageScreen.loading('Opening your cafe…');

        final cafe = snap.data!;
        if (!cafe.exists) {
          return const _SignOutMessage(
            icon: Icons.store_mall_directory_outlined,
            title: 'Cafe not found',
            message: 'The cafe linked to your account does not exist. Please contact the administrator.',
          );
        }

        final access = evaluateCafeAccess(cafe.data() ?? const {}, DateTime.now());
        switch (access.state) {
          case CafeAccessState.blocked:
            return _SignOutMessage(icon: Icons.block_rounded, title: access.title, message: access.message);
          case CafeAccessState.migrating:
            return _SignOutMessage(icon: Icons.construction_rounded, title: access.title, message: access.message);
          case CafeAccessState.allowed:
          case CafeAccessState.allowedWithWarning:
            break;
        }

        // Every cafe-scoped query (orders, menu, settings) now resolves under
        // cafes/{this user's cafeId}. Firestore rules enforce the same.
        FirestorePaths.setActiveCafe(user.cafeId);

        // A cafe login (manager role) chooses Manager or Captain view after
        // signing in; a captain-only account goes straight to the kitchen.
        final cafeName = (cafe.data()?['name'] ?? 'Your cafe').toString();
        final dashboard = user.isManager ? _ModeChooser(cafeName: cafeName) : const CaptainShell();
        // Always the same widget structure, so the dashboard (and any
        // half-entered order) survives the banner appearing/disappearing.
        return _WarningBanner(
          message: access.state == CafeAccessState.allowedWithWarning ? access.message : null,
          child: dashboard,
        );
      },
    );
  }
}

/// Thin banner above the dashboard (e.g. "Subscription expires in 3 days").
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message, required this.child});
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final msg = message;
    final p = context.palette;
    return Material(
      color: p.canvas,
      child: Column(
        children: [
          if (msg != null)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: p.warningTint,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: p.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(msg, style: TextStyle(color: p.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            key: const ValueKey('cafe-dashboard'),
            child: MediaQuery.removePadding(context: context, removeTop: msg != null, child: child),
          ),
        ],
      ),
    );
  }
}

class _SignOutMessage extends StatelessWidget {
  const _SignOutMessage({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MessageScreen(
      icon: icon,
      title: title,
      message: message,
      actionLabel: 'Sign out',
      onAction: () => signOutToLogin(context),
    );
  }
}

/// After a cafe login: "Manager" (POS, billing, menu) or "Captain"
/// (orders + kitchen). The choice can be switched later from the top bar.
class _ModeChooser extends StatefulWidget {
  const _ModeChooser({required this.cafeName});
  final String cafeName;

  @override
  State<_ModeChooser> createState() => _ModeChooserState();
}

class _ModeChooserState extends State<_ModeChooser> {
  String? _mode; // 'manager' | 'captain'

  @override
  Widget build(BuildContext context) {
    if (_mode == 'manager') return ManagerShell(onSwitchMode: () => setState(() => _mode = 'captain'));
    if (_mode == 'captain') return CaptainShell(onSwitchMode: () => setState(() => _mode = 'manager'));
    final p = context.palette;

    Widget option(String mode, IconData icon, String title, String subtitle) => Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Material(
            color: p.surface,
            shape: RoundedRectangleBorder(borderRadius: Radii.cardR, side: BorderSide(color: p.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _mode = mode),
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: p.primaryTint, borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: p.primary, size: 28),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.text.titleLarge),
                          const SizedBox(height: 2),
                          Text(subtitle, style: TextStyle(color: p.inkSubtle)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: p.inkSubtle),
                  ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: p.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.cafeName, textAlign: TextAlign.center, style: context.text.headlineMedium),
                const SizedBox(height: 4),
                Text('How are you working today?', textAlign: TextAlign.center, style: TextStyle(color: p.inkSubtle)),
                const SizedBox(height: Space.xl),
                option('manager', Icons.point_of_sale_rounded, 'Manager', 'Dashboard, orders, billing, menu, reports'),
                option('captain', Icons.room_service_outlined, 'Captain', 'Take orders, tables and kitchen'),
                const SizedBox(height: Space.sm),
                TextButton.icon(
                  onPressed: () => signOutToLogin(context),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
