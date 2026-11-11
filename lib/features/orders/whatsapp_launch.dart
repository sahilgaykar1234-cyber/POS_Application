import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'whatsapp_bill.dart';

/// Opens the WhatsApp chat with [number] and [text] typed in:
/// the WhatsApp app on phones, WhatsApp Web on computers (re-using one tab).
/// Falls back to wa.me. Returns false if nothing could be opened.
Future<bool> openWhatsAppChat(String number, String text) async {
  final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  try {
    final ok = await launchUrl(
      whatsAppDirectUri(number, text, mobile: mobile),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: mobile ? null : 'cafepos_whatsapp',
    );
    if (ok) return true;
  } catch (_) {}
  try {
    return await launchUrl(whatsAppUri(number, text), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
