import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;

import 'share_card_palette.dart';

/// Publishes one song's metadata and artwork so crawlers can read its Open
/// Graph tags from the initial HTML response. Override the deployed Worker
/// origin with --dart-define=SOUNDNEED_SHARE_BASE_URL=https://...workers.dev.
class SongShareService {
  SongShareService._();

  static const String _baseUrl = String.fromEnvironment(
    'SOUNDNEED_SHARE_BASE_URL',
    defaultValue: 'https://soundneed-shares.breinermuleth64.workers.dev',
  );
  static final Random _secureRandom = Random.secure();

  static Future<Uri> createSongLink({
    required String title,
    required String artist,
    required String album,
    required String deepLink,
    required Uint8List artwork,
  }) async {
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.path.isNotEmpty && base.path != '/') {
      throw StateError(
        'El sitio público de enlaces de SoundNeed no está configurado.',
      );
    }

    final id = _newId();
    final shareArtwork = await _resizeCover(artwork);
    final previewImage = await _buildPreviewImage(
      artwork: shareArtwork,
      title: title,
      artist: artist,
      album: album,
    );
    final coverType = _imageMimeType(shareArtwork);
    final response = await http
        .post(
          base.replace(path: '/api/share'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'id': id,
            'title': title,
            'artist': artist,
            'album': album,
            'deepLink': deepLink,
            'coverType': coverType,
            'coverBase64': base64Encode(shareArtwork),
            'previewType': 'image/jpeg',
            'previewWidth': 1080,
            'previewHeight': 1440,
            'previewBase64': base64Encode(previewImage),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'No se pudo preparar el enlace de la canción.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String)
          message = body['error'] as String;
      } catch (_) {}
      throw StateError(message);
    }

    final body = jsonDecode(response.body);
    final link = body is Map
        ? Uri.tryParse(body['url']?.toString() ?? '')
        : null;
    if (link == null ||
        link.scheme != 'https' ||
        link.host != base.host ||
        link.pathSegments.length != 2 ||
        link.pathSegments.first != 's') {
      throw StateError('El sitio devolvió un enlace de canción no válido.');
    }
    return link;
  }

  static String _newId() {
    final bytes = List<int>.generate(12, (_) => _secureRandom.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<Uint8List> _resizeCover(Uint8List source) async {
    for (final edge in const [320, 256, 192]) {
      final codec = await ui.instantiateImageCodec(
        source,
        targetWidth: edge,
        targetHeight: edge,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null && data.lengthInBytes <= 450 * 1024) {
            return data.buffer.asUint8List();
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    throw StateError(
      'La portada ocupa demasiado espacio para crear el enlace.',
    );
  }

  static String _imageMimeType(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    throw StateError('No se pudo reconocer el formato de la portada.');
  }

  static Future<Uint8List> _buildPreviewImage({
    required Uint8List artwork,
    required String title,
    required String artist,
    required String album,
  }) async {
    const width = 1080;
    const height = 1440;
    const white = Color(0xfff5f8f6);
    final palette = ShareCardPalette.fromArtwork(artwork);
    final codec = await ui.instantiateImageCodec(artwork);
    final frame = await codec.getNextFrame();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, 1080.0, 1440.0);

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.primary, const Color(0xff07130f), palette.secondary],
        ).createShader(bounds),
    );

    final aura = Paint()
      ..shader =
          RadialGradient(
            colors: [
              palette.accent.withValues(alpha: .30),
              palette.primary.withValues(alpha: .08),
              const Color(0xff07130f).withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: const Offset(540, 570), radius: 720),
          );
    canvas.drawRect(bounds, aura);

    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(28, 28, 1024, 1384),
      const Radius.circular(48),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xe6091712));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.accent.withValues(alpha: .2),
    );

    const coverRect = Rect.fromLTWH(90, 194, 900, 732);
    final coverRRect = RRect.fromRectAndRadius(
      coverRect,
      const Radius.circular(38),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(70, 174, 940, 772),
        const Radius.circular(46),
      ),
      Paint()..color = palette.accent.withValues(alpha: .16),
    );
    canvas.save();
    canvas.clipRRect(coverRRect);
    final sourceSize = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    // Fill the wider frame with the artwork so it keeps its visual presence.
    // Cropping, when needed, follows BoxFit.cover instead of shrinking the art.
    final fitted = applyBoxFit(BoxFit.cover, sourceSize, coverRect.size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & sourceSize,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      coverRect,
    );
    canvas.drawImageRect(
      frame.image,
      sourceRect,
      destinationRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    void drawText(
      String text, {
      required double x,
      required double y,
      required double maxWidth,
      required double fontSize,
      required Color color,
      int maxLines = 1,
      FontWeight fontWeight = FontWeight.w500,
      double letterSpacing = 0,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      painter.paint(canvas, Offset(x, y));
    }

    drawText(
      'SOUNDNEED',
      x: 82,
      y: 76,
      maxWidth: 400,
      fontSize: 27,
      color: white,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    drawText(
      'CANCIÓN COMPARTIDA',
      x: 82,
      y: 115,
      maxWidth: 500,
      fontSize: 17,
      color: palette.accent,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.3,
    );
    final badge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(794, 77, 204, 54),
      const Radius.circular(27),
    );
    canvas.drawRRect(
      badge,
      Paint()..color = palette.accent.withValues(alpha: .12),
    );
    drawText(
      'SOUND LINK',
      x: 816,
      y: 94,
      maxWidth: 160,
      fontSize: 17,
      color: palette.accent,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
    );
    drawText(
      title.trim().isEmpty ? 'Canción compartida' : title.trim(),
      x: 82,
      y: 977,
      maxWidth: 916,
      fontSize: 58,
      color: white,
      maxLines: 2,
      fontWeight: FontWeight.w700,
    );
    drawText(
      artist.trim(),
      x: 84,
      y: 1124,
      maxWidth: 912,
      fontSize: 32,
      color: const Color(0xffc3cec7),
    );
    if (album.trim().isNotEmpty) {
      drawText(
        album.trim(),
        x: 84,
        y: 1168,
        maxWidth: 912,
        fontSize: 24,
        color: const Color(0xff96a79c),
      );
    }

    final actionRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(82, 1230, 322, 68),
      const Radius.circular(34),
    );
    canvas.drawRRect(actionRect, Paint()..color = palette.accent);
    drawText(
      '▶   ABRIR EN SOUNDNEED',
      x: 106,
      y: 1251,
      maxWidth: 280,
      fontSize: 19,
      color: const Color(0xff071510),
      fontWeight: FontWeight.w700,
      letterSpacing: .5,
    );

    canvas.drawLine(
      const Offset(82, 1343),
      const Offset(998, 1343),
      Paint()
        ..strokeWidth = 1.5
        ..color = palette.accent.withValues(alpha: .18),
    );
    drawText(
      'Compartido desde SoundNeed',
      x: 84,
      y: 1366,
      maxWidth: 900,
      fontSize: 18,
      color: const Color(0xffd7e4db),
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    try {
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('No se pudo crear la vista previa.');
      final decoded = img.decodePng(png.buffer.asUint8List());
      if (decoded == null)
        throw StateError('No se pudo preparar la vista previa.');
      var jpg = Uint8List(0);
      for (final quality in const [86, 82, 78, 74, 70]) {
        jpg = img.encodeJpg(decoded, quality: quality);
        if (jpg.length <= 450 * 1024) break;
      }
      if (jpg.length > 450 * 1024) {
        throw StateError(
          'La vista previa ocupa demasiado espacio para compartirla.',
        );
      }
      return Uint8List.fromList(jpg);
    } finally {
      rendered.dispose();
      picture.dispose();
      frame.image.dispose();
      codec.dispose();
    }
  }

  static Future<Uri?> resolveSongLink(Uri shareLink) async {
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null ||
        shareLink.scheme != 'https' ||
        shareLink.host != base.host ||
        shareLink.pathSegments.length != 2 ||
        shareLink.pathSegments.first != 's') {
      return null;
    }
    final response = await http
        .get(base.replace(path: '/api/song/${shareLink.pathSegments.last}'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    final link = body is Map
        ? Uri.tryParse(body['deepLink']?.toString() ?? '')
        : null;
    if (link == null || link.scheme != 'soundneed' || link.host != 'track') {
      return null;
    }
    return link;
  }
}
