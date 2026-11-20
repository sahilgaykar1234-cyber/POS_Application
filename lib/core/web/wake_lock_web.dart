import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

JSObject? _lock;
bool _wanted = false;
bool _listening = false;

/// Keeps the screen on while [on] (a Print Station must not go to sleep).
/// Browsers drop the lock when the tab is hidden, so it is asked for again
/// when the page is shown.
Future<void> keepScreenOn(bool on) async {
  _wanted = on;
  if (!on) {
    final lock = _lock;
    _lock = null;
    try {
      if (lock != null) await lock.callMethod<JSPromise<JSAny?>>('release'.toJS).toDart;
    } catch (_) {}
    return;
  }
  if (!_listening) {
    _listening = true;
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (_wanted && web.document.visibilityState == 'visible') _request();
      }).toJS,
    );
  }
  await _request();
}

Future<void> _request() async {
  final nav = globalContext['navigator'] as JSObject?;
  final wl = nav?['wakeLock'];
  if (wl == null || wl.isUndefinedOrNull) return;
  try {
    _lock = await (wl as JSObject).callMethod<JSPromise<JSObject>>('request'.toJS, 'screen'.toJS).toDart;
  } catch (_) {
    // Not allowed right now (e.g. battery saver): the station still works
    // while the screen is on.
  }
}
