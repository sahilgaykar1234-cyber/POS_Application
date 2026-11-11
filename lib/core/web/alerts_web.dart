import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

web.AudioContext? _ctx;

/// Short two-tone "ding-dong" made with Web Audio (no sound file needed).
void playOrderChime() {
  try {
    final ctx = _ctx ??= web.AudioContext();
    if (ctx.state == 'suspended') ctx.resume();
    final t = ctx.currentTime;
    void tone(double freq, double start, double length) {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.0001, t + start);
      gain.gain.exponentialRampToValueAtTime(0.35, t + start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + start + length);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t + start);
      osc.stop(t + start + length + 0.05);
    }

    tone(880, 0, 0.35);
    tone(660, 0.28, 0.5);
  } catch (_) {
    // Browser blocked audio (no user interaction yet) – the pop-up still shows.
  }
}

bool get systemAlertsSupported {
  try {
    return globalContext.has('Notification');
  } catch (_) {
    return false;
  }
}

String get systemAlertPermission {
  if (!systemAlertsSupported) return 'denied';
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'denied';
  }
}

Future<String> requestSystemAlerts() async {
  if (!systemAlertsSupported) return 'denied';
  try {
    final r = await web.Notification.requestPermission().toDart;
    return r.toDart;
  } catch (_) {
    return systemAlertPermission;
  }
}

void showSystemAlert(String title, String body, {String? tag}) {
  if (systemAlertPermission != 'granted') return;
  try {
    if (!web.document.hidden) return; // the in-app pop-up is enough
    final n = web.Notification(title, web.NotificationOptions(body: body, icon: 'favicon.png', tag: tag ?? ''));
    n.onclick = ((web.Event _) {
      web.window.focus();
      n.close();
    }).toJS;
  } catch (_) {}
}
