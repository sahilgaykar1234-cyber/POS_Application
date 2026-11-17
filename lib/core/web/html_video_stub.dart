import 'package:flutter/widgets.dart';

/// The browser's own video player is web-only; elsewhere there is none
/// (callers show a fallback).
bool get canPlayHtmlVideo => false;

Widget htmlVideo(String src, {String? poster}) => const SizedBox.shrink();
