import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/data/firestore_paths.dart';
import '../../core/utils/business_day.dart';

/// The cafe's business & receipt settings (cafes/{id}/settings/business).
/// Field names are unchanged from the original app.
class BusinessSettings {
  BusinessSettings(this.data);

  final Map<String, dynamic> data;

  static final empty = BusinessSettings(const {});

  String _s(String k, [String d = '']) => (data[k] ?? d).toString();

  String get shopName => _s('shopName');
  String get tagline => _s('tagline');
  String get ownerName => _s('ownerName');
  String get mobileNumber => _s('mobileNumber');
  String get email => _s('email');
  String get gstNumber => _s('gstNumber');
  String get address => _s('address');
  String? get logoBase64 {
    final v = data['shopLogoBase64'];
    return v is String && v.isNotEmpty ? v : null;
  }

  String get receiptHeader => _s('receiptHeader', 'Thank you for your order!');
  String get receiptFooter => _s('receiptFooter', 'Visit Again!');
  String get thankYouMessage => _s('thankYouMessage', 'Thank You!');
  bool get showGst => data['showGst'] == true;
  double get gstPercent => double.tryParse(_s('gstPercentage', '5')) ?? 5.0;
  String get currencySymbol => _s('currencySymbol', '₹');
  String get currencyCode => _s('currencyCode', 'INR');
  String get defaultOrderType => _s('defaultOrderType', 'Dine-In');
  String get defaultTax => _s('defaultTax', '5');
  bool get autoGenBillNumber => data['autoGenBillNumber'] ?? true;
  bool get autoGenTokenNumber => data['autoGenTokenNumber'] ?? true;

  /// Minutes after midnight when the business day ends ("dayEndsAt": "05:00").
  int get dayEndsAtMinutes {
    final m = BusinessDay.parse(data['dayEndsAt']);
    return m == null || m > BusinessDay.maxCutoffMinutes ? BusinessDay.defaultCutoffMinutes : m;
  }
  int get numberOfTables {
    final n = int.tryParse(_s('numberOfTables', '12')) ?? 12;
    return n > 0 ? n : 12;
  }

  /// The map receipts and the thermal printer expect (same keys as before).
  Map<String, dynamic> get receiptSettings => {
        'shopLogoBase64': logoBase64,
        'shopName': shopName,
        'tagline': tagline,
        'address': address,
        'mobileNumber': mobileNumber,
        'gstNumber': gstNumber,
        'receiptHeader': receiptHeader,
        'receiptFooter': receiptFooter,
        'thankYouMessage': thankYouMessage,
        'showGst': showGst,
        'gstPercentage': _s('gstPercentage', '5'),
      };
}

class BusinessSettingsRepository {
  BusinessSettingsRepository._();
  static final instance = BusinessSettingsRepository._();

  Stream<BusinessSettings> watch() => FirestorePaths.businessSettings().snapshots().map((d) => _apply(BusinessSettings(d.data() ?? const {})));

  Future<BusinessSettings> load() async {
    final d = await FirestorePaths.businessSettings().get();
    return _apply(BusinessSettings(d.data() ?? const {}));
  }

  /// Every screen uses the cafe's business-day end time from here on.
  static BusinessSettings _apply(BusinessSettings s) {
    BusinessDay.setCutoff(s.dayEndsAtMinutes);
    return s;
  }

  Future<void> save(Map<String, dynamic> fields) =>
      FirestorePaths.businessSettings().set({...fields, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
}
