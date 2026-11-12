import 'dart:typed_data';

/// Result of trying to hand a file to the phone's share sheet.
enum ShareFileResult { shared, cancelled, unsupported }

/// Browser printing is web-only.
bool get canPrintHtml => false;
Future<void> printHtml(String html) async => throw UnsupportedError('Printing needs the web app');

bool canShareFile(String fileName, String mimeType) => false;
Future<ShareFileResult> shareFile(Uint8List bytes, String fileName, String mimeType, {String? text}) async =>
    ShareFileResult.unsupported;

void downloadFile(Uint8List bytes, String fileName, String mimeType) {}
