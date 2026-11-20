import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_service.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/utils/formatters.dart';
import '../orders/bill_numbers.dart';

/// Print Station: a phone or computer that has the receipt printer connected
/// (USB or Bluetooth) prints bills sent from other devices – for example an
/// iPhone, where the browser can't reach a printer.
///
/// Bills go through Firestore: cafes/{cafeId}/printJobs/{id}
///   pending → printing → printed | failed   (expired if never picked up)

class PrintJobStatus {
  PrintJobStatus._();
  static const pending = 'pending';
  static const printing = 'printing';
  static const printed = 'printed';
  static const failed = 'failed';
  static const expired = 'expired';
}

class PrintJob {
  PrintJob(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get status => (data['status'] ?? PrintJobStatus.pending).toString();
  String get label => (data['label'] ?? '').toString();
  String get orderId => (data['orderId'] ?? '').toString();
  String get error => (data['error'] ?? '').toString();
  Map<String, dynamic> get order => data['order'] is Map ? Map<String, dynamic>.from(data['order'] as Map) : const {};
  DateTime? get createdAt => Fmt.toDate(data['createdAt']);
}

/// The Print Station as other devices see it.
class StationInfo {
  StationInfo(this.data);
  final Map<String, dynamic> data;

  String get device => (data['device'] ?? '').toString();
  DateTime? get lastSeen => Fmt.toDate(data['lastSeen']);

  /// Heard from in the last few minutes.
  bool isOnline(DateTime now) => lastSeen != null && now.difference(lastSeen!) < const Duration(minutes: 3);
}

class PrintStationService {
  PrintStationService._();
  static final instance = PrintStationService._();

  /// A bill not picked up in this time is not printed any more (it would
  /// come out long after the customer left).
  static const staleAfter = Duration(minutes: 30);

  /// Whether THIS device is the Print Station (saved on the device).
  final ValueNotifier<bool> enabled = ValueNotifier(false);

  static String _prefKey(String cafeId) => 'cafe_pos_print_station_$cafeId';

  Future<void> load(String cafeId) async {
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_prefKey(cafeId)) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  Future<void> setEnabled(String cafeId, bool on) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey(cafeId), on);
    } catch (_) {}
  }

  // ------------------------------------------------------------ sending --

  /// Short text for the station screen, e.g. "26-27/0042 · Table 4".
  static String labelFor(Map<String, dynamic> order, String orderId) {
    final bill = displayBillNo(order, orderId);
    final table = (order['tableNo'] ?? '').toString().trim();
    final token = order['tokenNo'];
    final where = table.isNotEmpty ? table : (token != null ? 'Token #$token' : '');
    return [if (bill.isNotEmpty) bill, if (where.isNotEmpty) where].join(' · ');
  }

  /// Queues [order] for the Print Station. Returns the job id.
  Future<String> send({required Map<String, dynamic> order, required String orderId}) async {
    final user = AuthService.instance.currentUser;
    final ref = FirestorePaths.printJobs().doc();
    final write = ref.set({
      'order': {
        for (final e in order.entries)
          if (e.value is! FieldValue) e.key: e.value,
      },
      'orderId': orderId,
      'label': labelFor(order, orderId),
      'status': PrintJobStatus.pending,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user?.uid ?? '',
      'createdByName': user?.displayName ?? '',
    });
    // Offline: the bill is kept and sent when the internet is back.
    await write.timeout(const Duration(seconds: 10), onTimeout: () {});
    return ref.id;
  }

  /// The job's final state, or null if it is still waiting after [timeout].
  Future<PrintJob?> waitForResult(String jobId, {Duration timeout = const Duration(seconds: 25)}) async {
    try {
      return await FirestorePaths.printJobs()
          .doc(jobId)
          .snapshots()
          .map((d) => d.exists ? PrintJob(d.id, d.data()!) : null)
          .firstWhere((j) => j != null && const [PrintJobStatus.printed, PrintJobStatus.failed, PrintJobStatus.expired].contains(j.status))
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Stream<StationInfo?> watchStation() =>
      FirestorePaths.printStation().snapshots().map((d) => d.exists ? StationInfo(d.data()!) : null);

  // ------------------------------------------------------------ station --

  /// Bills waiting to be printed, oldest first.
  Stream<List<PrintJob>> watchPending() => FirestorePaths.printJobs()
      .where('status', isEqualTo: PrintJobStatus.pending)
      .snapshots()
      .map((s) => s.docs.map((d) => PrintJob(d.id, d.data())).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0))));

  /// Takes the job for this station so it is printed only once. null = it
  /// was taken already, or is too old (then marked expired).
  Future<PrintJob?> claim(String jobId, String stationId, {DateTime? now}) {
    final ref = FirestorePaths.printJobs().doc(jobId);
    return FirestorePaths.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return null;
      final job = PrintJob(snap.id, snap.data()!);
      if (job.status != PrintJobStatus.pending) return null;
      final created = job.createdAt;
      if (created != null && (now ?? DateTime.now()).difference(created) > staleAfter) {
        tx.update(ref, {'status': PrintJobStatus.expired});
        return null;
      }
      tx.update(ref, {'status': PrintJobStatus.printing, 'stationId': stationId, 'claimedAt': FieldValue.serverTimestamp()});
      return job;
    });
  }

  Future<void> markPrinted(String jobId) =>
      FirestorePaths.printJobs().doc(jobId).update({'status': PrintJobStatus.printed, 'printedAt': FieldValue.serverTimestamp()});

  /// The printer was not ready: the bill waits until it is connected.
  Future<void> putBack(String jobId) => FirestorePaths.printJobs().doc(jobId).update({'status': PrintJobStatus.pending});

  Future<void> markFailed(String jobId, String error) =>
      FirestorePaths.printJobs().doc(jobId).update({'status': PrintJobStatus.failed, 'error': error});

  Future<void> heartbeat({required String stationId, required String device}) =>
      FirestorePaths.printStation().set({'stationId': stationId, 'device': device, 'lastSeen': FieldValue.serverTimestamp()});

  /// Removes finished jobs older than a day (customer data is not kept).
  Future<void> cleanUp({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    final done = await FirestorePaths.printJobs()
        .where('status', whereIn: const [PrintJobStatus.printed, PrintJobStatus.failed, PrintJobStatus.expired])
        .limit(200)
        .get();
    for (final d in done.docs) {
      final created = Fmt.toDate(d.data()['createdAt']);
      if (created == null || created.isBefore(cutoff)) await d.reference.delete();
    }
  }
}
