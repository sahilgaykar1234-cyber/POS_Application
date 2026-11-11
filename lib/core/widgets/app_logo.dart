import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Neutral platform logo, used where a cafe has not uploaded its own logo.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 50});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Icon(Icons.storefront_rounded, color: AppColors.primary, size: size * 0.55),
    );
  }
}
