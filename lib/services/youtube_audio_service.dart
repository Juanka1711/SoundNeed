import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeAudioService {
  YouTubeAudioService._();

  static final YouTubeAudioService instance =
      YouTubeAudioService._();

  final YoutubeExplode _youtube = YoutubeExplode();

  static const MethodChannel _youtubeChannel =
      MethodChannel('youtube/extractor');

  /// Último error ocurrido.
  /// null = última operación exitosa.
  String? lastError;

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 '
      '(KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36';

  // ============================================================
  // BUSCAR
  // ============================================================

  Future<List<YouTubeSearchResult>> search(
    String query,
  ) async {
    query = query.trim();

    if (query.isEmpty) {
      return [];
    }

    lastError = null;

    // ----------------------------------------------------------
    // 1. youtube_explode_dart
    // ----------------------------------------------------------

    try {
      final results = await _youtube.search.search(query);

      final list = results
          .map(
            (video) => YouTubeSearchResult(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              duration:
                  video.duration?.inSeconds ?? 0,
              thumbnail:
                  video.thumbnails.highResUrl,
              url:
                  'https://www.youtube.com/watch?v=${video.id.value}',
            ),
          )
          .where(
            (result) =>
                result.videoId.isNotEmpty &&
                result.title.isNotEmpty,
          )
          .toList();

      debugPrint(
        '[YouTubeAudioService] '
        'Librería: ${list.length} resultados',
      );

      if (list.isNotEmpty) {
        lastError = null;
        return list;
      }
    } catch (e, st) {
      lastError = 'Librería: $e';

      debugPrint(
        '[YouTubeAudioService] '
        'Error en librería: $e',
      );

      debugPrint('$st');
    }

    // ----------------------------------------------------------
    // 2. Fallback HTML
    // ----------------------------------------------------------

    try {
      final list = await _searchByHtml(query);

      debugPrint(
        '[YouTubeAudioService] '
        'Respaldo HTML: ${list.length} resultados',
      );

      if (list.isNotEmpty) {
        lastError = null;
        return list;
      }

      lastError ??=
          'La búsqueda no devolvió videos.';
    } catch (e, st) {
      lastError =
          '${lastError ?? ''} | Respaldo: $e';

      debugPrint(
        '[YouTubeAudioService] '
        'Error en respaldo HTML: $e',
      );

      debugPrint('$st');
    }

    return [];
  }

  // ============================================================
  // BÚSQUEDA HTML
  // ============================================================

  Future<List<YouTubeSearchResult>> _searchByHtml(
    String query,
  ) async {
    final uri = Uri.https(
      'www.youtube.com',
      '/results',
      {
        'search_query': query,
        'hl': 'es',
      },
    );

    final response = await http
        .get(
          uri,
          headers: {
            'User-Agent': _desktopUserAgent,
            'Accept-Language':
                'es-ES,es;q=0.9,en;q=0.8',
            'Cookie':
                'CONSENT=YES+1; SOCS=CAI',
          },
        )
        .timeout(
          const Duration(seconds: 15),
        );

    debugPrint(
      '[YouTubeAudioService] '
      'HTTP ${response.statusCode}, '
      '${response.body.length} caracteres',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'HTTP ${response.statusCode}',
      );
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

    final data = jsonDecode(
      match.group(1)!,
    );

    final results =
        <YouTubeSearchResult>[];

    _collectVideos(
      data,
      results,
    );

    return results;
  }

  // ============================================================
  // EXTRAER VIDEOS DEL HTML
  // ============================================================

  void _collectVideos(
    dynamic node,
    List<YouTubeSearchResult> out,
  ) {
    if (out.length >= 30) {
      return;
    }

    if (node is Map) {
      final renderer =
          node['videoRenderer'];

      if (renderer is Map &&
          renderer['videoId'] is String) {
        final videoId =
            renderer['videoId'] as String;

        final thumbs =
            renderer['thumbnail'] is Map
                ? (renderer['thumbnail']
                            ['thumbnails']
                        as List? ??
                    [])
                : <dynamic>[];

        String thumbnail = '';

        if (thumbs.isNotEmpty &&
            thumbs.last is Map) {
          thumbnail =
              (thumbs.last['url'] ?? '')
                  .toString();

          if (thumbnail.startsWith('//')) {
            thumbnail =
                'https:$thumbnail';
          }
        }

        final title =
            _text(renderer['title']);

        if (title.isNotEmpty) {
          out.add(
            YouTubeSearchResult(
              videoId: videoId,
              title: title,
              artist: _text(
                renderer['ownerText'] ??
                    renderer['longBylineText'],
              ),
              duration: _toSeconds(
                _text(
                  renderer['lengthText'],
                ),
              ),
              thumbnail: thumbnail,
              url:
                  'https://www.youtube.com/watch?v=$videoId',
            ),
          );
        }

        return;
      }

      for (final value in node.values) {
        _collectVideos(
          value,
          out,
        );
      }
    } else if (node is List) {
      for (final value in node) {
        _collectVideos(
          value,
          out,
        );
      }
    }
  }

  // ============================================================
  // TEXTO Y DURACIÓN
  // ============================================================

  String _text(dynamic object) {
    if (object is Map) {
      if (object['simpleText'] is String) {
        return object['simpleText'] as String;
      }

      if (object['runs'] is List) {
        return (object['runs'] as List)
            .map(
              (run) => run is Map
                  ? (run['text'] ?? '').toString()
                  : '',
            )
            .join();
      }
    }

    return '';
  }

  int _toSeconds(String text) {
    if (text.isEmpty) {
      return 0;
    }

    var total = 0;

    for (final part in text.split(':')) {
      total =
          total * 60 +
          (int.tryParse(part.trim()) ?? 0);
    }

    return total;
  }

  // ============================================================
  // AUDIO
  // ============================================================

  /// Obtiene la URL directa de audio desde NewPipe
  /// mediante el código nativo de Android.
  ///
  /// La selección del stream compatible ocurre en
  /// MainActivity.kt.
  ///
  /// Este método solamente:
  /// - solicita la URL;
  /// - aplica timeout;
  /// - valida la URL;
  /// - maneja errores.
  Future<String?> getAudioUrl(
    String videoId,
  ) async {
    lastError = null;

    videoId = videoId.trim();

    if (videoId.isEmpty) {
      lastError =
          'El videoId está vacío.';

      debugPrint(
        '[YouTubeAudioService] '
        'videoId vacío',
      );

      return null;
    }

    try {
      debugPrint(
        '[YouTubeAudioService] '
        'Solicitando audio para: $videoId',
      );

      final result =
          await _youtubeChannel
              .invokeMethod<String>(
        'getAudioUrl',
        {
          'videoId': videoId,
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      // --------------------------------------------------------
      // Respuesta vacía
      // --------------------------------------------------------

      if (result == null ||
          result.trim().isEmpty) {
        lastError =
            'Android no devolvió una URL de audio.';

        debugPrint(
          '[YouTubeAudioService] '
          'Respuesta de Android vacía',
        );

        return null;
      }

      final url = result.trim();

      // --------------------------------------------------------
      // Validación de URL
      // --------------------------------------------------------

      final uri = Uri.tryParse(url);

      if (uri == null) {
        lastError =
            'La URL de audio no pudo analizarse.';

        debugPrint(
          '[YouTubeAudioService] '
          'URL imposible de analizar',
        );

        return null;
      }

      if (!uri.hasScheme ||
          !uri.hasAuthority) {
        lastError =
            'La URL de audio no es válida.';

        debugPrint(
          '[YouTubeAudioService] '
          'URL sin scheme/authority: $url',
        );

        return null;
      }

      if (uri.scheme != 'http' &&
          uri.scheme != 'https') {
        lastError =
            'Protocolo de audio no compatible: '
            '${uri.scheme}';

        debugPrint(
          '[YouTubeAudioService] '
          'Protocolo inválido: ${uri.scheme}',
        );

        return null;
      }

      // --------------------------------------------------------
      // Éxito
      // --------------------------------------------------------

      lastError = null;

      debugPrint(
        '[YouTubeAudioService] '
        'URL de audio válida: '
        '${uri.scheme}://${uri.host}',
      );

      return url;
    }

    // ----------------------------------------------------------
    // Timeout
    // ----------------------------------------------------------

    on TimeoutException catch (e, st) {
      lastError =
          'Timeout al obtener URL de audio (20s).';

      debugPrint(
        '[YouTubeAudioService] '
        'Timeout en getAudioUrl: $e',
      );

      debugPrint('$st');

      return null;
    }

    // ----------------------------------------------------------
    // Error de plataforma
    // ----------------------------------------------------------

    on PlatformException catch (e, st) {
      lastError =
          'NewPipe: ${e.code}: '
          '${e.message ?? 'sin detalles'}';

      debugPrint(
        '[YouTubeAudioService] '
        'PlatformException: '
        '${e.code} ${e.message}',
      );

      debugPrint('$st');

      return null;
    }

    // ----------------------------------------------------------
    // Error inesperado
    // ----------------------------------------------------------

    catch (e, st) {
      lastError =
          'Error obteniendo audio: $e';

      debugPrint(
        '[YouTubeAudioService] '
        'Error inesperado: $e',
      );

      debugPrint('$st');

      return null;
    }
  }

  /// Obtiene los metadatos publicados por la página original del video.
  Future<Map<String, String>> getVideoMetadata(String videoId) async {
    try {
      final metadata = await _youtubeChannel.invokeMapMethod<String, dynamic>(
        'getVideoMetadata',
        {'videoId': videoId},
      ).timeout(const Duration(seconds: 20));
      if (metadata == null) return const {};
      return metadata.map((key, value) => MapEntry(key, value?.toString().trim() ?? ''));
    } catch (error) {
      debugPrint('[YouTubeAudioService] No se pudieron leer metadatos del video: $error');
      return const {};
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _youtube.close();
  }
}

// ================================================================
// RESULTADO DE BÚSQUEDA
// ================================================================

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
