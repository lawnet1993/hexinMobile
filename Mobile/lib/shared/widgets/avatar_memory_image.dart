import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Keeps the encoded source reusable while decoding only the pixels needed by
/// an avatar. Unlike a square resize, this preserves non-square faces and lets
/// CircleAvatar apply its existing cover crop.
final class AvatarMemoryImage extends MemoryImage {
  const AvatarMemoryImage(super.bytes, {required this.diameter});

  final int diameter;

  /// Small size buckets avoid multiple GPU images for near-identical layouts.
  static int decodeDiameter(double radius, double devicePixelRatio) {
    final logical = radius.isFinite && radius > 0 ? radius * 2 : 32.0;
    final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final physical = (logical * ratio).clamp(1.0, 512.0).ceil();
    return ((physical + 15) ~/ 16) * 16;
  }

  static ui.TargetImageSize targetSize(int width, int height, int diameter) {
    if (width <= 0 || height <= 0 || diameter <= 0) {
      throw ArgumentError('Avatar dimensions must be positive');
    }
    // Cover needs the shorter side to fill the circle; cap the longest side as
    // well so a pathological panorama cannot bypass the decoded-memory bound.
    final coverScale = diameter.clamp(1, 512) / math.min(width, height);
    final scale = math.min(
      1.0,
      math.min(coverScale, 1024 / math.max(width, height)),
    );
    return ui.TargetImageSize(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  @override
  ImageStreamCompleter loadImage(
    MemoryImage key,
    ImageDecoderCallback decode,
  ) => super.loadImage(
    key,
    (buffer, {getTargetSize}) => decode(
      buffer,
      getTargetSize: (width, height) => targetSize(width, height, diameter),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is AvatarMemoryImage &&
      super == other &&
      diameter == other.diameter;

  @override
  int get hashCode => Object.hash(super.hashCode, diameter);
}
