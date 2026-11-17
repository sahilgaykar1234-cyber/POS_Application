import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool get canPlayHtmlVideo => true;

final Set<String> _registered = {};

/// The browser's own <video> player (play/pause, seek, volume, full screen),
/// shown inside Flutter. The file is only downloaded once this is on screen.
Widget htmlVideo(String src, {String? poster}) {
  final viewType = 'html-video:$src';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final v = web.document.createElement('video') as web.HTMLVideoElement;
      v.src = src;
      if (poster != null) v.poster = poster;
      v.controls = true;
      v.autoplay = true; // opened by a tap, so browsers allow it
      v.playsInline = true;
      v.preload = 'auto';
      v.setAttribute('controlsList', 'nodownload');
      v.style.cssText = 'width:100%;height:100%;object-fit:contain;background:#000;border:0;';
      return v;
    });
  }
  return HtmlElementView(viewType: viewType);
}
