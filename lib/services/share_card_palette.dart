import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ShareCardPalette {
  const ShareCardPalette({
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  final Color primary;
  final Color secondary;
  final Color accent;

  static ShareCardPalette fromArtwork(Uint8List? bytes) {
    final decoded = bytes == null ? null : img.decodeImage(bytes);
    if (decoded == null) {
      return const ShareCardPalette(
        primary: Color(0xff102c23),
        secondary: Color(0xff262044),
        accent: Color(0xff79e5a6),
      );
    }

    final buckets = List<_ColorBucket>.generate(12, (_) => _ColorBucket());
    final stepX = (decoded.width ~/ 24).clamp(1, decoded.width).toInt();
    final stepY = (decoded.height ~/ 24).clamp(1, decoded.height).toInt();
    for (var y = 0; y < decoded.height; y += stepY) {
      for (var x = 0; x < decoded.width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final maximum = [r, g, b].reduce((a, value) => a > value ? a : value);
        final minimum = [r, g, b].reduce((a, value) => a < value ? a : value);
        final delta = maximum - minimum;
        if (maximum < 24 || maximum > 248 || delta < 12) continue;

        var hue = 0.0;
        if (maximum == r) {
          hue = 60 * (((g - b) / delta) % 6);
        } else if (maximum == g) {
          hue = 60 * ((b - r) / delta + 2);
        } else {
          hue = 60 * ((r - g) / delta + 4);
        }
        hue = (hue + 360) % 360;
        buckets[(hue ~/ 30).clamp(0, 11).toInt()].add(r, g, b);
      }
    }

    final ranked = buckets.where((bucket) => bucket.count > 0).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (ranked.isEmpty) return fromArtwork(null);

    final dominant = ranked.first.average;
    final secondary = ranked.length > 1
        ? ranked.firstWhere(
            (bucket) => (bucket.average.hue - dominant.hue).abs() >= 50,
            orElse: () => ranked[1],
          ).average
        : const _Rgb(30, 174, 158, 180);
    final accentSource = _Rgb(
      ((dominant.r + secondary.r) / 2).round(),
      ((dominant.g + secondary.g) / 2).round(),
      ((dominant.b + secondary.b) / 2).round(),
      0,
    );

    return ShareCardPalette(
      primary: _darken(dominant, .34),
      secondary: _darken(secondary, .25),
      accent: _lighten(accentSource, .46),
    );
  }

  static Color _darken(_Rgb color, double factor) => Color.fromARGB(
        255,
        (color.r * factor).round().clamp(0, 255).toInt(),
        (color.g * factor).round().clamp(0, 255).toInt(),
        (color.b * factor).round().clamp(0, 255).toInt(),
      );

  static Color _lighten(_Rgb color, double amount) => Color.fromARGB(
        255,
        (color.r + (255 - color.r) * amount).round().clamp(0, 255).toInt(),
        (color.g + (255 - color.g) * amount).round().clamp(0, 255).toInt(),
        (color.b + (255 - color.b) * amount).round().clamp(0, 255).toInt(),
      );
}

class _ColorBucket {
  int count = 0;
  int red = 0;
  int green = 0;
  int blue = 0;

  void add(int r, int g, int b) {
    count++;
    red += r;
    green += g;
    blue += b;
  }

  _Rgb get average => _Rgb(
        red ~/ count,
        green ~/ count,
        blue ~/ count,
        _hue(red ~/ count, green ~/ count, blue ~/ count),
      );
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b, this.hue);

  final int r;
  final int g;
  final int b;
  final double hue;
}

double _hue(int r, int g, int b) {
  final maximum = [r, g, b].reduce((a, value) => a > value ? a : value);
  final minimum = [r, g, b].reduce((a, value) => a < value ? a : value);
  final delta = maximum - minimum;
  if (delta == 0) return 0;
  final hue = maximum == r
      ? 60 * (((g - b) / delta) % 6)
      : maximum == g
          ? 60 * ((b - r) / delta + 2)
          : 60 * ((r - g) / delta + 4);
  return (hue + 360) % 360;
}
