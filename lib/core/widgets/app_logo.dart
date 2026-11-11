import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Neutral platform logo, used where a cafe has not uploaded its own logo.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 50});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(size * 0.26)),
      child: Icon(Icons.storefront_rounded, color: p.onPrimary, size: size * 0.55),
    );
  }
}
