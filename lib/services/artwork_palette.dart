import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colors selected from an album cover and tuned for a dark interface.
@immutable
class ArtworkPalette {
  const ArtworkPalette({
    required this.primary,
    required this.secondary,
    required this.dark,
    required this.isArtworkDerived,
  });

  static const neutral = ArtworkPalette(
    primary: Color(0xFF8B5CF6),
    secondary: Color(0xFFEC4899),
    dark: Color(0xFF0B0B12),
    isArtworkDerived: false,
  );

  final Color primary;
  final Color secondary;
  final Color dark;
  final bool isArtworkDerived;
}

/// Decodes a tiny thumbnail and extracts two distinct, saturated colors.
/// This keeps the result fast to calculate while ignoring transparent and
/// near-black pixels that would make the app background muddy.
abstract final class ArtworkPaletteExtractor {
  static Future<ArtworkPalette> fromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return ArtworkPalette.neutral;

    ui.Codec? codec;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 24,
      );
      image = (await codec.getNextFrame()).image;

      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || data.lengthInBytes < 4) {
        return ArtworkPalette.neutral;
      }

      final samples = <_ColorSample>[];
      for (var offset = 0; offset + 3 < data.lengthInBytes; offset += 4) {
        final alpha = data.getUint8(offset + 3);
        if (alpha < 180) continue;

        final color = Color.fromARGB(
          255,
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        );
        final hsl = HSLColor.fromColor(color);

        if (hsl.lightness < 0.08 ||
            (hsl.saturation < 0.10 &&
                hsl.lightness > 0.20 &&
                hsl.lightness < 0.85)) {
          continue;
        }

        final saturationScore = hsl.saturation.clamp(0.0, 1.0);
        final lightnessScore =
            1 - ((hsl.lightness - 0.52).abs() / 0.52).clamp(0.0, 1.0);

        samples.add(
          _ColorSample(color, saturationScore * 0.65 + lightnessScore * 0.35),
        );
      }

      if (samples.isEmpty) return ArtworkPalette.neutral;
      samples.sort((a, b) => b.score.compareTo(a.score));

      final primary = _prepareColor(samples.first.color);
      var secondary = primary;
      for (final sample in samples.skip(1)) {
        final candidate = _prepareColor(sample.color);
        if (_colorDistance(primary, candidate) > 0.18) {
          secondary = candidate;
          break;
        }
      }

      if (secondary == primary) {
        final hsl = HSLColor.fromColor(primary);
        secondary = hsl
            .withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0))
            .toColor();
      }

      final primaryHsl = HSLColor.fromColor(primary);
      final dark = primaryHsl
          .withLightness(0.07)
          .withSaturation(
            (primaryHsl.saturation * 0.75).clamp(0.0, 1.0).toDouble(),
          )
          .toColor();

      return ArtworkPalette(
        primary: primary,
        secondary: secondary,
        dark: dark,
        isArtworkDerived: true,
      );
    } catch (_) {
      return ArtworkPalette.neutral;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Color _prepareColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final saturation = hsl.saturation.clamp(0.35, 0.90).toDouble();
    final lightness = hsl.lightness < 0.30
        ? 0.48
        : hsl.lightness > 0.78
        ? 0.62
        : hsl.lightness;

    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  static double _colorDistance(Color a, Color b) {
    final ahsl = HSLColor.fromColor(a);
    final bhsl = HSLColor.fromColor(b);
    final rawHueDistance = (ahsl.hue - bhsl.hue).abs();
    final hueDistance = rawHueDistance > 180
        ? 360 - rawHueDistance
        : rawHueDistance;

    return hueDistance / 360 * 0.5 +
        (ahsl.saturation - bhsl.saturation).abs() * 0.3 +
        (ahsl.lightness - bhsl.lightness).abs() * 0.2;
  }
}

class _ColorSample {
  const _ColorSample(this.color, this.score);

  final Color color;
  final double score;
}
