import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pos_app/core/i18n/tr.dart';

import 'renewal_service.dart';

/// Pop-up each time a cafe login opens the app while the plan is ending. The
/// number of days comes from the Super Admin's "Warn before expiry" setting.
/// A Manager can pay from here; other logins are told to ask the Manager.
class RenewalReminder extends StatefulWidget {
  const RenewalReminder({super.key, required this.cafeId, required this.child, this.message, this.expired = false, this.onPay});

  final String cafeId;
  final Widget child;

  /// null = nothing to remind about (or the setting is still loading).
  final String? message;

  /// The expiry date has passed and the cafe is in its grace period.
  final bool expired;

  /// Opens "Pay now". null for logins that can't pay.
  final VoidCallback? onPay;

  @override
  State<RenewalReminder> createState() => _RenewalReminderState();
}

class _RenewalReminderState extends State<RenewalReminder> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(RenewalReminder old) {
    super.didUpdateWidget(old);
    _check();
  }

  void _check() {
    if (_done || widget.message == null) return;
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_show()));
  }

  /// A payment already sent is being verified: don't ask for it again.
  Future<bool> _alreadyPaid() async {
    if (widget.onPay == null) return false; // only a Manager can see claims
    try {
      final claim = await RenewalService.instance.watchClaim(widget.cafeId).first.timeout(const Duration(seconds: 5));
      return claim?.isPending ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _show() async {
    if (await _alreadyPaid() || !mounted) return;
    final message = widget.message;
    if (message == null) return;
    final canPay = widget.onPay != null;
    final pay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('renew-reminder'),
        icon: Icon(widget.expired ? Icons.error_outline_rounded : Icons.event_busy_outlined),
        title: Text(widget.expired ? tr('Subscription expired') : tr('Subscription ending soon')),
        content: Text(canPay ? message : '$message ${tr('Ask your manager to renew.')}'),
        actions: canPay
            ? [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Later'))),
                FilledButton(key: const Key('renew-reminder-pay'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Pay now'))),
              ]
            : [FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('OK')))],
      ),
    );
    if (pay == true && mounted) widget.onPay?.call();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
