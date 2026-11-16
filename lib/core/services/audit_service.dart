import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../data/firestore_paths.dart';

/// Records what cafe staff did (void a bill, edit a paid bill, export data,
/// delete a customer's data…) in auditLogs. The rules only let a user add
/// entries in their own name for their own cafe; nobody can edit or delete
/// them. Never pass passwords, tokens or full phone numbers in [details].
class AuditService {
  AuditService._();
  static final instance = AuditService._();

  Future<void> log(String action, {String? cafeId, Map<String, dynamic>? details}) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await FirestorePaths.auditLogs().add({
        'action': action,
        'actorUid': user.uid,
        'actorRole': user.role?.claim ?? 'unknown',
        'actorName': user.displayName,
        'cafeId': cafeId ?? user.cafeId,
        'details': details ?? const {},
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Logging must never block the action itself.
      debugPrint('audit $action not saved: $e');
    }
  }
}

/// 9825012345 → 98XXXXX345 (for logs and screens that don't need the number).
String maskPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length < 6) return d.isEmpty ? '' : 'XXXX';
  return '${d.substring(0, 2)}${'X' * (d.length - 5)}${d.substring(d.length - 3)}';
}
