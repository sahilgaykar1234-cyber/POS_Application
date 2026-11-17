import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// Optional Manager PIN of a cafe (Settings › Security). With a shared cafe
/// login, the PIN keeps kitchen/counter staff out of the Manager view (sales,
/// cancelling bills, settings). Only a salted hash is stored, never the PIN.
///
/// This is a counter-side lock. For real separation give the kitchen its own
/// "Kitchen only" login (Super Admin › cafe › Staff), which the server rules
/// keep out of billing entirely.
class ManagerPin {
  ManagerPin._();

  static String newSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// Many rounds of SHA-256 so guessing from the stored hash is slow.
  static String hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }

  static bool isValid(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  static bool matches(String pin, {required String? salt, required String? hash}) =>
      salt != null && hash != null && ManagerPin.hash(pin, salt) == hash;
}

/// Asks for the Manager PIN. Returns true when it matches.
Future<bool> askManagerPin(BuildContext context, {required String salt, required String hash}) async {
  final ctrl = TextEditingController();
  var wrong = 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      void check() {
        if (ManagerPin.matches(ctrl.text, salt: salt, hash: hash)) {
          Navigator.pop(ctx, true);
        } else {
          setState(() {
            wrong++;
            ctrl.clear();
          });
        }
      }

      return AlertDialog(
        title: Text(tr('Manager PIN')),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Enter the Manager PIN to open the Manager view.')),
            const SizedBox(height: Space.md),
            TextField(
              key: const Key('manager-pin'),
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tr('PIN'), errorText: wrong == 0 ? null : tr('Wrong PIN{0}', [wrong >= 3 ? tr(' – ask the manager') : ''])),
              onSubmitted: (_) => check(),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('manager-pin-ok'), onPressed: check, child: Text(tr('Open'))),
        ],
      );
    }),
  );
  return ok == true;
}
