import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../auth/app_user.dart';
import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../data/firestore_paths.dart';

/// A staff member as listed in staff management.
class StaffMember {
  const StaffMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole? role;

  /// invited | active | disabled
  final String status;

  bool get isDisabled => status == 'disabled';

  factory StaffMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StaffMember(
      uid: doc.id,
      email: (d['email'] ?? '').toString(),
      displayName: (d['displayName'] ?? '').toString(),
      role: UserRole.fromClaim(d['role']),
      status: (d['status'] ?? 'active').toString(),
    );
  }
}

/// Staff operations. Anything privileged goes through Cloud Functions, which
/// re-check permissions server-side; this class never edits roles directly.
class StaffService {
  StaffService._();
  static final StaffService instance = StaffService._();

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);

  /// Live list of a cafe's staff, managers first, then by name.
  Stream<List<StaffMember>> watchCafeStaff(String cafeId) {
    return FirestorePaths.users().where('cafeId', isEqualTo: cafeId).snapshots().map((snap) {
      final list = snap.docs.map(StaffMember.fromDoc).toList();
      list.sort((a, b) {
        final r = (a.role?.index ?? 99).compareTo(b.role?.index ?? 99);
        return r != 0 ? r : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
      return list;
    });
  }

  /// Creates the account and emails a "set your password" link.
  /// Returns the same link so it can also be shared (e.g. WhatsApp).
  Future<String> invite({
    required String email,
    required String displayName,
    required UserRole role,
    required String cafeId,
  }) async {
    final res = await _fn.httpsCallable('inviteStaff').call<Map<String, dynamic>>({
      'email': email,
      'displayName': displayName,
      'role': role.claim,
      'cafeId': cafeId,
    });
    await _sendEmailQuietly(email);
    return (res.data['setupLink'] ?? '').toString();
  }

  /// Admin-initiated reset: emails the user a reset link and returns it.
  /// The admin never sees or sets the password itself.
  Future<String> sendPasswordReset(StaffMember member) async {
    final res = await _fn.httpsCallable('createPasswordResetLink').call<Map<String, dynamic>>({
      'uid': member.uid,
    });
    await _sendEmailQuietly(member.email);
    return (res.data['link'] ?? '').toString();
  }

  Future<void> setActive(StaffMember member, bool active) async {
    await _fn.httpsCallable('setStaffActive').call<Map<String, dynamic>>({
      'uid': member.uid,
      'active': active,
    });
  }

  // The link is already returned for manual sharing, so a failed email send
  // (e.g. quota) should not fail the whole action.
  Future<void> _sendEmailQuietly(String email) async {
    try {
      await AuthService.instance.sendPasswordResetEmail(email);
    } catch (_) {}
  }
}
