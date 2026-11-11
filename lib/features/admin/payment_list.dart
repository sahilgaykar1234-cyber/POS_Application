import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'subscription_receipt.dart';

/// Payment history rows with a "download receipt" action.
class PaymentList extends StatelessWidget {
  const PaymentList({super.key, required this.payments, this.showCafe = true});

  final List<SubscriptionPayment> payments;
  final bool showCafe;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No payments recorded yet.', style: TextStyle(color: Colors.white54)),
      );
    }
    return Column(
      children: [
        for (final p in payments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: Icon(Icons.receipt_long, color: AppColors.success, size: 20),
            ),
            title: Text(
              '${Fmt.money(p.amount)}${showCafe ? '  ·  ${p.cafeName}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                p.receiptNo,
                Fmt.date(p.paidAt),
                p.method,
                if (p.referenceId.isNotEmpty) 'Ref ${p.referenceId}',
                if (p.periodEnd != null) 'till ${Fmt.date(p.periodEnd)}',
              ].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              tooltip: 'Download receipt',
              icon: const Icon(Icons.download_outlined),
              onPressed: () async {
                try {
                  await shareSubscriptionReceipt(p);
                } catch (_) {
                  if (context.mounted) showError(context, 'Could not create the receipt PDF.');
                }
              },
            ),
          ),
      ],
    );
  }
}
