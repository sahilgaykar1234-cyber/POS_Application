import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

enum ShareFileResult { shared, cancelled, unsupported }

bool get canPrintHtml => true;

/// Prints [html] from a hidden iframe: only the receipt is printed, never the
/// app around it. Resolves when the print dialog has been opened.
Future<void> printHtml(String html) async {
  final frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
  frame.setAttribute('aria-hidden', 'true');
  frame.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0;pointer-events:none;';
  final loaded = Completer<void>();
  frame.onload = ((web.Event _) {
    if (!loaded.isCompleted) loaded.complete();
  }).toJS;
  frame.srcdoc = html.toJS;
  web.document.body!.append(frame);
  await loaded.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  // Let the logo image decode before the print snapshot.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final w = frame.contentWindow;
  if (w == null) throw StateError('Could not open the print view');
  w.focus();
  w.print();
  // Keep the frame while the print dialog may still read it.
  Timer(const Duration(minutes: 1), frame.remove);
}

web.File _file(Uint8List bytes, String fileName, String mimeType) =>
    web.File([bytes.toJS].toJS, fileName, web.FilePropertyBag(type: mimeType));

bool canShareFile(String fileName, String mimeType) {
  try {
    final probe = _file(Uint8List(1), fileName, mimeType);
    return web.window.navigator.canShare(web.ShareData(files: [probe].toJS));
  } catch (_) {
    return false;
  }
}

/// Opens the phone's share sheet with the file attached (the user picks
/// WhatsApp and the chat, then sends). Nothing is sent automatically.
Future<ShareFileResult> shareFile(Uint8List bytes, String fileName, String mimeType, {String? text}) async {
  final f = _file(bytes, fileName, mimeType);
  final data = text == null ? web.ShareData(files: [f].toJS) : web.ShareData(files: [f].toJS, text: text);
  try {
    if (!web.window.navigator.canShare(data)) return ShareFileResult.unsupported;
    await web.window.navigator.share(data).toDart;
    return ShareFileResult.shared;
  } catch (e) {
    // AbortError = the user closed the share sheet.
    return e.toString().contains('AbortError') ? ShareFileResult.cancelled : ShareFileResult.unsupported;
  }
}

/// Saves the file (e.g. to attach it in WhatsApp Web).
void downloadFile(Uint8List bytes, String fileName, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
