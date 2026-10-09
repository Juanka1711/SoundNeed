import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;

import 'share_card_palette.dart';

class PlaylistShareService {
  PlaylistShareService._();

  static const String _baseUrl = String.fromEnvironment(
    'SOUNDNEED_SHARE_BASE_URL',
    defaultValue: 'https://soundneed-shares.breinermuleth64.workers.dev',
  );
  static final Random _secureRandom = Random.secure();

  static Future<Uri> createPlaylistLink({
    required String name,
    required int songCount,
    required String payload,
    required List<Uint8List?> coverArtworks,
  }) async {
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw StateError('El sitio público de SoundNeed no está configurado.');
    }
    if (name.trim().isEmpty || songCount <= 0 || payload.isEmpty) {
      throw StateError('La playlist no tiene información para compartir.');
    }

    final id = _newId();
    final preview = await _buildPreview(
      name: name.trim(),
      songCount: songCount,
      coverArtworks: coverArtworks,
    );
    final response = await http
        .post(
          base.replace(path: '/api/playlist'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'id': id,
            'name': name.trim(),
            'songCount': songCount,
            'payload': payload,
            'previewType': 'image/jpeg',
            'previewBase64': base64Encode(preview),
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'No se pudo preparar el enlace de la playlist.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) {
          message = body['error'] as String;
        }
      } catch (_) {}
      throw StateError(message);
    }

    final body = jsonDecode(response.body);
    final link = body is Map ? Uri.tryParse(body['url']?.toString() ?? '') : null;
    if (link == null ||
        link.scheme != 'https' ||
        link.host != base.host ||
        link.pathSegments.length != 2 ||
        link.pathSegments.first != 'p') {
      throw StateError('El sitio devolvió un enlace de playlist no válido.');
    }
    return link;
  }

  static Future<String?> resolvePlaylistLink(Uri shareLink) async {
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null ||
        shareLink.scheme != 'https' ||
        shareLink.host != base.host ||
        shareLink.pathSegments.length != 2 ||
        shareLink.pathSegments.first != 'p') {
      return null;
    }
    return resolvePlaylistId(shareLink.pathSegments.last);
  }

  static Future<String?> resolvePlaylistId(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{12,24}$').hasMatch(id)) return null;
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null || base.scheme != 'https' || base.host.isEmpty) return null;
    final response = await http
        .get(
          base.replace(
            path: '/api/playlist/$id',
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    return body is Map ? body['payload']?.toString() : null;
  }

  static String _newId() => base64UrlEncode(
        List<int>.generate(12, (_) => _secureRandom.nextInt(256)),
      ).replaceAll('=', '');

  static Future<Uint8List> _buildPreview({
    required String name,
    required int songCount,
    required List<Uint8List?> coverArtworks,
  }) async {
    const width = 1200;
    const height = 630;
    const darkInk = Color(0xff07130f);
    final usableCovers = coverArtworks.take(4).toList(growable: false);
    final palette = ShareCardPalette.fromArtwork(
      usableCovers.cast<Uint8List?>().firstWhere(
            (cover) => cover != null && cover.isNotEmpty,
            orElse: () => null,
          ),
    );
    final images = <ui.Image?>[];
    for (final bytes in usableCovers) {
      if (bytes == null || bytes.isEmpty) {
        images.add(null);
        continue;
      }
      try {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 280,
          targetHeight: 280,
        );
        try {
          images.add((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      } catch (_) {
        images.add(null);
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, 1200, 630);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.primary, const Color(0xff08130f), .25)!,
            const Color(0xff07110f),
            Color.lerp(palette.secondary, const Color(0xff0d111c), .32)!,
          ],
        ).createShader(bounds),
    );

    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(30, 30, 1140, 570),
      const Radius.circular(42),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xe6091712));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.accent.withValues(alpha: .22),
    );

    const mosaicRect = Rect.fromLTWH(76, 94, 424, 424);
    final mosaicFrame = RRect.fromRectAndRadius(
      mosaicRect,
      const Radius.circular(32),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(66, 84, 444, 444),
        const Radius.circular(40),
      ),
      Paint()..color = palette.accent.withValues(alpha: .12),
    );
    canvas.save();
    canvas.clipRRect(mosaicFrame);
    canvas.drawRect(mosaicRect, Paint()..color = const Color(0xff18211e));
    const gap = 7.0;
    const tile = (424 - gap) / 2;
    for (var index = 0; index < 4; index++) {
      final coverIndex = images.isEmpty ? -1 : index % images.length;
      final image = coverIndex < 0 ? null : images[coverIndex];
      final x = 76.0 + (index % 2) * (tile + gap);
      final y = 94.0 + (index ~/ 2) * (tile + gap);
      final destination = Rect.fromLTWH(x, y, tile, tile);
      if (image == null) {
        canvas.drawRect(
          destination,
          Paint()..color = Color.lerp(palette.primary, darkInk, .38)!,
        );
        _drawText(
          canvas,
          '♫',
          x: x,
          y: y + tile * .29,
          maxWidth: tile,
          fontSize: 92,
          color: palette.accent.withValues(alpha: .78),
          align: TextAlign.center,
        );
      } else {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          destination,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }
    canvas.restore();

    _drawText(
      canvas,
      'SOUNDNEED  ·  PLAYLIST COMPARTIDA',
      x: 552,
      y: 112,
      maxWidth: 555,
      fontSize: 19,
      color: palette.accent,
      letterSpacing: 1.8,
    );
    _drawText(
      canvas,
      name,
      x: 552,
      y: 176,
      maxWidth: 560,
      fontSize: 48,
      color: const Color(0xfff5f8f6),
      maxLines: 2,
    );
    _drawText(
      canvas,
      '$songCount ${songCount == 1 ? 'canción' : 'canciones'}',
      x: 552,
      y: 313,
      maxWidth: 550,
      fontSize: 28,
      color: const Color(0xffc3cec7),
    );

    final action = RRect.fromRectAndRadius(
      const Rect.fromLTWH(552, 390, 366, 70),
      const Radius.circular(35),
    );
    canvas.drawRRect(action, Paint()..color = palette.accent);
    _drawText(
      canvas,
      '▶   Abrir en SoundNeed',
      x: 576,
      y: 412,
      maxWidth: 330,
      fontSize: 22,
      color: darkInk,
    );

    canvas.drawLine(
      const Offset(76, 552),
      const Offset(1124, 552),
      Paint()
        ..strokeWidth = 1.5
        ..color = const Color(0x33e5f4e9),
    );
    _drawText(
      canvas,
      'Compartida desde SoundNeed  ·  Lista para guardar en tu biblioteca',
      x: 78,
      y: 566,
      maxWidth: 1040,
      fontSize: 18,
      color: const Color(0xffd7e4db),
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    try {
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('No se pudo crear la tarjeta.');
      final decoded = img.decodePng(png.buffer.asUint8List());
      if (decoded == null) throw StateError('No se pudo preparar la tarjeta.');
      for (final quality in const [84, 76, 68, 60]) {
        final jpg = img.encodeJpg(decoded, quality: quality);
        if (jpg.length <= 450 * 1024) return Uint8List.fromList(jpg);
      }
      throw StateError('La tarjeta supera el tamaño permitido para compartir.');
    } finally {
      rendered.dispose();
      picture.dispose();
      for (final image in images) {
        image?.dispose();
      }
    }
  }

  static void _drawText(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    required double maxWidth,
    required double fontSize,
    required Color color,
    int maxLines = 1,
    double letterSpacing = 0,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
  }
}
