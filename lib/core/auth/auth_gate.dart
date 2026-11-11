import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../captain_dashboard.dart';
import '../../features/admin/super_admin_home_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../manager_dashboard.dart';
import '../data/firestore_paths.dart';
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
            message: 'Your account (${appUser.email}) has no role assigned yet. '
                'Please ask your manager or the administrator to set it up.',
          );
        }

        if (appUser.isSuperAdmin) return const SuperAdminHomeScreen();
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

        final data = cafe.data() ?? const {};
        final status = (data['status'] ?? 'active').toString();
        final cafeName = (data['name'] ?? 'Your cafe').toString();

        if (status == 'suspended' || status == 'inactive' || status == 'deleted') {
          return _SignOutMessage(
            icon: Icons.block_rounded,
            title: '$cafeName is currently unavailable',
            message: 'Access to this cafe has been paused. Your data is safe. '
                'Please contact the administrator.',
          );
        }

        // SAFETY (until the Phase 3 migration): existing POS screens still use
        // the old shared collections, which hold Flamy Wood's data. Only the
        // cafe flagged `legacyData` may open them, so no other cafe can ever
        // see that data.
        if (data['legacyData'] != true) {
          return _SignOutMessage(
            icon: Icons.construction_rounded,
            title: '$cafeName is being set up',
            message: 'Your account is ready, but your cafe\'s POS is not live yet. '
                'You will be able to use it soon.',
          );
        }

        return user.isManager ? const ManagerDashboardScreen() : const CaptainDashboardScreen();
      },
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
