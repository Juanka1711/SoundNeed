import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeAudioService {
  YouTubeAudioService._();

  static final YouTubeAudioService instance = YouTubeAudioService._();

  final YoutubeExplode _youtube = YoutubeExplode();

  /// Último error ocurrido al buscar (null si todo salió bien).
  String? lastError;

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  // ============================================================
  // BUSCAR
  // ============================================================

  Future<List<YouTubeSearchResult>> search(String query) async {
    query = query.trim();
    if (query.isEmpty) return [];

    lastError = null;

    // 1) Intento con la librería
    try {
      final results = await _youtube.search.search(query);

      final list = results
          .map(
            (video) => YouTubeSearchResult(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              duration: video.duration?.inSeconds ?? 0,
              thumbnail: video.thumbnails.highResUrl,
              url: 'https://www.youtube.com/watch?v=${video.id.value}',
            ),
          )
          .where((r) => r.videoId.isNotEmpty && r.title.isNotEmpty)
          .toList();

      debugPrint(
        '[YouTubeAudioService] Librería: ${list.length} resultados',
      );

      if (list.isNotEmpty) return list;
    } catch (e, st) {
      lastError = 'Librería: $e';
      debugPrint('[YouTubeAudioService] Error en librería: $e');
      debugPrint('$st');
    }

    // 2) Respaldo: leer la página de resultados directamente
    try {
      final list = await _searchByHtml(query);

      debugPrint(
        '[YouTubeAudioService] Respaldo HTML: ${list.length} resultados',
      );

      if (list.isNotEmpty) {
        lastError = null;
        return list;
      }

      lastError ??= 'La búsqueda no devolvió videos.';
    } catch (e, st) {
      lastError = '${lastError ?? ''} | Respaldo: $e';
      debugPrint('[YouTubeAudioService] Error en respaldo HTML: $e');
      debugPrint('$st');
    }

    return [];
  }

  Future<List<YouTubeSearchResult>> _searchByHtml(String query) async {
    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': query,
      'hl': 'es',
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': _desktopUserAgent,
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
        // Evita la pantalla de consentimiento de cookies
        'Cookie': 'CONSENT=YES+1; SOCS=CAI',
      },
    ).timeout(const Duration(seconds: 15));

    debugPrint(
      '[YouTubeAudioService] HTTP ${response.statusCode}, '
      '${response.body.length} caracteres',
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final match = RegExp(
      r'var ytInitialData\s*=\s*(\{.*?\});\s*</script>',
      dotAll: true,
    ).firstMatch(response.body);

    if (match == null) {
      throw Exception(
        'No se encontró ytInitialData '
        '(¿página de consentimiento o bloqueo?)',
      );
    }

    final data = jsonDecode(match.group(1)!);

    final results = <YouTubeSearchResult>[];
    _collectVideos(data, results);

    return results;
  }

  void _collectVideos(dynamic node, List<YouTubeSearchResult> out) {
    if (out.length >= 30) return;

    if (node is Map) {
      final renderer = node['videoRenderer'];

      if (renderer is Map && renderer['videoId'] is String) {
        final videoId = renderer['videoId'] as String;

        final thumbs = renderer['thumbnail'] is Map
            ? (renderer['thumbnail']['thumbnails'] as List? ?? [])
            : <dynamic>[];

        String thumbnail = '';
        if (thumbs.isNotEmpty && thumbs.last is Map) {
          thumbnail = (thumbs.last['url'] ?? '').toString();
          if (thumbnail.startsWith('//')) thumbnail = 'https:$thumbnail';
        }

        final title = _text(renderer['title']);

        if (title.isNotEmpty) {
          out.add(
            YouTubeSearchResult(
              videoId: videoId,
              title: title,
              artist: _text(
                renderer['ownerText'] ?? renderer['longBylineText'],
              ),
              duration: _toSeconds(_text(renderer['lengthText'])),
              thumbnail: thumbnail,
              url: 'https://www.youtube.com/watch?v=$videoId',
            ),
          );
        }

        return;
      }

      for (final value in node.values) {
        _collectVideos(value, out);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectVideos(value, out);
      }
    }
  }

  String _text(dynamic o) {
    if (o is Map) {
      if (o['simpleText'] is String) return o['simpleText'] as String;

      if (o['runs'] is List) {
        return (o['runs'] as List)
            .map((r) => r is Map ? (r['text'] ?? '').toString() : '')
            .join();
      }
    }

    return '';
  }

  int _toSeconds(String text) {
    if (text.isEmpty) return 0;

    var total = 0;

    for (final part in text.split(':')) {
      total = total * 60 + (int.tryParse(part.trim()) ?? 0);
    }

    return total;
  }

  // ============================================================
  // AUDIO
  // ============================================================

  /// Obtiene la URL de audio para un videoId.
  /// Prueba varios "clientes" de YouTube, porque si uno falla
  /// (VideoUnavailableException) otro suele funcionar.
  /// Estas URLs expiran en unas horas: pídela justo antes de reproducir.
  Future<String?> getAudioUrl(String videoId) async {
    final attempts = <(String, List<YoutubeApiClient>)>[
      ('ios', [YoutubeApiClient.ios]),
      ('androidVr', [YoutubeApiClient.androidVr]),
      ('tv', [YoutubeApiClient.tv]),
      ('safari', [YoutubeApiClient.safari]),
      ('android', [YoutubeApiClient.android]),
    ];

    final errors = <String>[];

    for (final (name, clients) in attempts) {
      try {
        final manifest = await _youtube.videos.streamsClient.getManifest(
          videoId,
          ytClients: clients,
        );

        final audioStreams = manifest.audioOnly;

        if (audioStreams.isEmpty) {
          errors.add('$name: sin streams de audio');
          debugPrint('[YouTubeAudioService] $name: sin streams de audio');
          continue;
        }

        // Preferimos m4a (mp4): es el mejor soportado en Android.
        final mp4 = audioStreams
            .where((s) => s.container == StreamContainer.mp4)
            .toList();

        final stream = mp4.isNotEmpty
            ? (mp4..sort((a, b) => b.bitrate.compareTo(a.bitrate))).first
            : audioStreams.withHighestBitrate();

        debugPrint('[YouTubeAudioService] Audio obtenido con cliente $name');

        return stream.url.toString();
      } catch (e) {
        final firstLine = e.toString().split('\n').first;
        errors.add('$name: $firstLine');
        debugPrint('[YouTubeAudioService] Cliente $name falló: $firstLine');
      }
    }

    lastError = 'Audio: ${errors.join(' | ')}';
    debugPrint('[YouTubeAudioService] Ningún cliente funcionó.');

    return null;
  }

  final Map<String, Future<String?>> _inFlight = {};

  /// Descarga el audio a la caché del teléfono y devuelve la ruta.
  /// Si ya hay una descarga en curso del mismo video, la reutiliza.
  Future<String?> getAudioFile(String videoId) {
    final existing = _inFlight[videoId];
    if (existing != null) return existing;

    final future = _getAudioFile(videoId).whenComplete(() {
      _inFlight.remove(videoId);
    });

    _inFlight[videoId] = future;
    return future;
  }

  /// Descarga el audio a la caché del teléfono y devuelve la ruta del archivo.
  ///
  /// ExoPlayer recibía "Source error" porque las URLs de YouTube exigen
  /// ciertos headers; descargando con el cliente HTTP de la propia librería
  /// evitamos ese problema. Además queda en caché: la segunda vez que
  /// reproduces la misma canción empieza al instante.
  Future<String?> _getAudioFile(String videoId) async {
    final dir = Directory('${Directory.systemTemp.path}/soundneed_audio');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // ¿Ya está descargada?
    for (final ext in const ['m4a', 'webm']) {
      final cached = File('${dir.path}/$videoId.$ext');

      if (await cached.exists() && await cached.length() > 0) {
        debugPrint('[YouTubeAudioService] Usando caché: ${cached.path}');
        return cached.path;
      }
    }

    final attempts = <(String, List<YoutubeApiClient>)>[
      ('ios', [YoutubeApiClient.ios]),
      ('androidVr', [YoutubeApiClient.androidVr]),
      ('tv', [YoutubeApiClient.tv]),
      ('safari', [YoutubeApiClient.safari]),
      ('android', [YoutubeApiClient.android]),
    ];

    final errors = <String>[];

    for (final (name, clients) in attempts) {
      File? part;

      try {
        final manifest = await _youtube.videos.streamsClient.getManifest(
          videoId,
          ytClients: clients,
        );

        final audioStreams = manifest.audioOnly;

        if (audioStreams.isEmpty) {
          errors.add('$name: sin streams de audio');
          debugPrint('[YouTubeAudioService] $name: sin streams de audio');
          continue;
        }

        final mp4 = audioStreams
            .where((s) => s.container == StreamContainer.mp4)
            .toList();

        final stream = mp4.isNotEmpty
            ? (mp4..sort((a, b) => b.bitrate.compareTo(a.bitrate))).first
            : audioStreams.withHighestBitrate();

        final ext = stream.container == StreamContainer.mp4 ? 'm4a' : 'webm';

        final file = File('${dir.path}/$videoId.$ext');
        part = File('${file.path}.part');

        debugPrint('[YouTubeAudioService] Descargando con cliente $name...');

        await _download(stream, part);

        if (await part.length() == 0) {
          throw Exception('descarga vacía');
        }

        await part.rename(file.path);

        debugPrint(
          '[YouTubeAudioService] Audio listo con cliente $name '
          '(${await file.length()} bytes)',
        );

        return file.path;
      } catch (e) {
        final firstLine = e.toString().split('\n').first;
        errors.add('$name: $firstLine');
        debugPrint('[YouTubeAudioService] Cliente $name falló: $firstLine');

        try {
          if (part != null && await part.exists()) {
            await part.delete();
          }
        } catch (_) {}
      }
    }

    lastError = 'Audio: ${errors.join(' | ')}';
    debugPrint('[YouTubeAudioService] Ningún cliente funcionó.');

    return null;
  }

  static const String _androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  /// Descarga el stream en [part]. Primero con la librería; si no llegan
  /// datos, con HTTP directo por trozos.
  Future<void> _download(AudioOnlyStreamInfo stream, File part) async {
    try {
      await _writeStream(
        _youtube.videos.streamsClient.get(stream),
        part,
        stream.size.totalBytes,
      );
      return;
    } catch (e) {
      debugPrint(
        '[YouTubeAudioService] Descarga con librería falló: '
        '${e.toString().split('\n').first}',
      );
    }

    debugPrint('[YouTubeAudioService] Probando descarga HTTP directa...');
    await _downloadChunked(stream, part);
  }

  /// Escribe un stream en disco. Si pasan 15 s sin recibir datos, falla
  /// (antes se quedaba colgado para siempre).
  Future<void> _writeStream(
    Stream<List<int>> source,
    File part,
    int expectedBytes,
  ) async {
    final sink = part.openWrite();
    var received = 0;
    var nextLog = 0;

    try {
      await for (final chunk in source.timeout(const Duration(seconds: 15))) {
        sink.add(chunk);
        received += chunk.length;

        if (received >= nextLog) {
          debugPrint('[YouTubeAudioService] Descargados ${received ~/ 1024} KB');
          nextLog += 512 * 1024;
        }
      }
    } finally {
      await sink.close();
    }

    if (received == 0) {
      throw Exception('no llegaron datos');
    }

    if (expectedBytes > 0 && received < expectedBytes) {
      throw Exception('descarga incompleta ($received de $expectedBytes)');
    }
  }

  /// Descarga con peticiones HTTP por trozos de 1 MB.
  Future<void> _downloadChunked(AudioOnlyStreamInfo stream, File part) async {
    const chunkSize = 1024 * 1024;
    final total = stream.size.totalBytes;
    final client = http.Client();
    final sink = part.openWrite();
    var start = 0;

    try {
      while (start < total) {
        final end = (start + chunkSize - 1 < total - 1)
            ? start + chunkSize - 1
            : total - 1;

        final response = await client.get(
          stream.url,
          headers: {
            'User-Agent': _androidUserAgent,
            'Range': 'bytes=$start-$end',
          },
        ).timeout(const Duration(seconds: 20));

        debugPrint(
          '[YouTubeAudioService] HTTP ${response.statusCode} '
          'bytes $start-$end (${response.bodyBytes.length})',
        );

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('HTTP ${response.statusCode}');
        }

        if (response.bodyBytes.isEmpty) {
          throw Exception('trozo vacío');
        }

        sink.add(response.bodyBytes);
        start += response.bodyBytes.length;
      }
    } finally {
      await sink.close();
      client.close();
    }
  }

  void dispose() {
    _youtube.close();
  }
}

class YouTubeSearchResult {
  final String videoId;
  final String title;
  final String artist;
  final int duration;
  final String thumbnail;
  final String url;

  const YouTubeSearchResult({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnail,
    required this.url,
  });
}
