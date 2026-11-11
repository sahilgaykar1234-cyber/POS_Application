import 'dart:js_interop';

import 'package:web/web.dart' as web;

String? _applied = '';

/// Sets the browser tab icon to the cafe's uploaded logo, or back to the
/// default Cafe POS icon when [logoBase64] is null.
void applyFavicon(String? logoBase64) {
  if (logoBase64 == _applied) return;
  _applied = logoBase64;

  final href = logoBase64 == null ? 'favicon.png' : 'data:${_mime(logoBase64)};base64,$logoBase64';
  final links = web.document.querySelectorAll('link[rel="icon"], link[rel="apple-touch-icon"]');
  for (var i = 0; i < links.length; i++) {
    final node = links.item(i);
    if (node != null && node.isA<web.HTMLLinkElement>()) {
      final link = node as web.HTMLLinkElement;
      link.href = href;
      if (link.rel == 'icon') link.type = logoBase64 == null ? 'image/png' : _mime(logoBase64);
    }
  }
}

String _mime(String b64) {
  if (b64.startsWith('/9j/')) return 'image/jpeg';
  if (b64.startsWith('UklGR')) return 'image/webp';
  if (b64.startsWith('R0lGOD')) return 'image/gif';
  if (b64.startsWith('PHN2Zy') || b64.startsWith('PD94bW')) return 'image/svg+xml';
  return 'image/png';
}
