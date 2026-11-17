import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/web/html_video.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// The product overview film (1:44, music only), served with the web app
/// from web/videos/. Nothing is downloaded until someone opens it.
const String kProductVideoPath = 'videos/product-overview.mp4';
const String kProductVideoPoster = 'videos/product-overview.jpg';
const String kProductVideoLength = '1:44';

/// "See how it works": plays the overview film in a pop-up. Never autoplays
/// on the login screen itself.
Future<void> showProductVideo(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => const _ProductVideoDialog(),
    );

class _ProductVideoDialog extends StatelessWidget {
  const _ProductVideoDialog();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    // As large as fits, 16:9, with room for the title bar.
    final width = (size.width - 32).clamp(0.0, 1100.0);
    final videoWidth = width.clamp(0.0, (size.height - 120) * 16 / 9);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: p.ink,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: videoWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Cafe POS in {0}', [kProductVideoLength]),
                      style: TextStyle(color: p.surface, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    key: const Key('product-video-close'),
                    tooltip: tr('Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: p.surface),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: canPlayHtmlVideo
                  ? htmlVideo(
                      Uri.base.resolve('/$kProductVideoPath').toString(),
                      poster: Uri.base.resolve('/$kProductVideoPoster').toString(),
                    )
                  : ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          tr('Open the web app to watch the video.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.surface),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The button on the login screen. [onDark] for the dark side panel.
class ProductVideoButton extends StatelessWidget {
  const ProductVideoButton({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = Text(tr('See how it works ({0})', [kProductVideoLength]));
    const icon = Icon(Icons.play_circle_fill_rounded, size: 22);
    if (onDark) {
      return FilledButton.icon(
        key: const Key('product-video'),
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        onPressed: () => showProductVideo(context),
        icon: icon,
        label: label,
      );
    }
    return OutlinedButton.icon(
      key: const Key('product-video'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () => showProductVideo(context),
      icon: icon,
      label: label,
    );
  }
}
