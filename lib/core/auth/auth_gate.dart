import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../captain_dashboard.dart';
import '../../features/admin/super_admin_shell.dart';
import '../../features/auth/login_screen.dart';
import '../../manager_dashboard.dart';
import '../data/firestore_paths.dart';
import '../subscription/cafe_access.dart';
import '../theme/app_theme.dart';
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

        final dashboard = user.isManager ? const ManagerDashboardScreen() : const CaptainDashboardScreen();
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
    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          if (msg != null)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: const Color(0xFF8A5A00),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
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
      iconColor: AppColors.accent,
      title: title,
      message: message,
      actionLabel: 'Sign out',
      onAction: () => signOutToLogin(context),
    );
  }
}
