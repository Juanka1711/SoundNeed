import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  factory YouTubeSearchResult.fromMap(Map<String, dynamic> map) {
    final videoId = map['video_id']?.toString() ?? '';

    return YouTubeSearchResult(
      videoId: videoId,
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      duration: int.tryParse(
            map['duration']?.toString() ?? '',
          ) ??
          0,
      thumbnail: map['thumbnail']?.toString() ?? '',
      url: 'https://www.youtube.com/watch?v=$videoId',
    );
  }
}

class YouTubeSearchService {
  YouTubeSearchService._();

  static final YouTubeSearchService instance =
      YouTubeSearchService._();

  WebViewController? _controller;

  Completer<bool>? _pageLoaded;

  WebViewController get controller {
    if (_controller == null) {
      throw StateError(
        'YouTubeSearchService todavía no fue inicializado.',
      );
    }

    return _controller!;
  }

  bool get isInitialized => _controller != null;

  Future<void> initialize() async {
    if (_controller != null) {
      return;
    }

    final controller = WebViewController();

    await controller.setJavaScriptMode(
      JavaScriptMode.unrestricted,
    );

    await controller.setBackgroundColor(
      const Color(0xFF000000),
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          debugPrint(
            '[SoundNeed YouTube] PAGE STARTED: $url',
          );
        },

        onPageFinished: (url) {
          debugPrint(
            '[SoundNeed YouTube] PAGE FINISHED: $url',
          );

          if (_pageLoaded != null &&
              !_pageLoaded!.isCompleted) {
            _pageLoaded!.complete(true);
          }
        },

        onWebResourceError: (error) {
          debugPrint(
            '[SoundNeed YouTube] WEB ERROR: '
            '${error.errorCode} '
            '${error.description}',
          );

          // IMPORTANTE:
          //
          // ERR_CACHE_MISS no significa que la página
          // completa haya fallado.
          //
          // No completamos el Future como false aquí.
          //
          // Esperamos a onPageFinished.
        },
      ),
    );

    _controller = controller;
  }

  Future<List<YouTubeSearchResult>> search(
    String query,
  ) async {
    query = query.trim();

    if (query.isEmpty) {
      return const [];
    }

    await initialize();

    final controller = _controller!;

    final encoded =
        Uri.encodeQueryComponent(query);

    final url =
        'https://www.youtube.com/results?search_query=$encoded';

    debugPrint('');
    debugPrint(
      '[SoundNeed YouTube] ============================',
    );
    debugPrint(
      '[SoundNeed YouTube] BUSCANDO: $query',
    );
    debugPrint(
      '[SoundNeed YouTube] URL: $url',
    );

    final pageLoaded = Completer<bool>();
    _pageLoaded = pageLoaded;

    await controller.loadRequest(
      Uri.parse(url),
    );

    bool loaded = false;

    try {
      loaded = await pageLoaded.future.timeout(
        const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint(
        '[SoundNeed YouTube] TIMEOUT esperando página: $e',
      );
    }

    if (!loaded) {
      debugPrint(
        '[SoundNeed YouTube] La página no terminó de cargar.',
      );

      return const [];
    }

    // Damos tiempo a YouTube para construir su estado.
    await Future<void>.delayed(
      const Duration(seconds: 2),
    );

    for (int attempt = 1; attempt <= 15; attempt++) {
      debugPrint(
        '[SoundNeed YouTube] Extracción $attempt/15',
      );

      try {
        final raw =
            await controller.runJavaScriptReturningResult(
          _extractJavaScript,
        );

        final normalized =
            _normalizeJavaScriptResult(raw);

        debugPrint(
          '[SoundNeed YouTube] DIAGNOSTICO: $normalized',
        );

        if (normalized.isEmpty) {
          await Future<void>.delayed(
            const Duration(milliseconds: 500),
          );
          continue;
        }

        final decoded = jsonDecode(normalized);

        if (decoded is! Map) {
          continue;
        }

        final items = decoded['items'];

        if (items is! List) {
          continue;
        }

        debugPrint(
          '[SoundNeed YouTube] Items: ${items.length}',
        );

        final results = items
            .whereType<Map>()
            .map(
              (item) => YouTubeSearchResult.fromMap(
                Map<String, dynamic>.from(item),
              ),
            )
            .where(
              (result) =>
                  result.videoId.isNotEmpty &&
                  result.title.isNotEmpty,
            )
            .toList();

        if (results.isNotEmpty) {
          debugPrint(
            '[SoundNeed YouTube] RESULTADOS: '
            '${results.length}',
          );

          return results;
        }
      } catch (e) {
        debugPrint(
          '[SoundNeed YouTube] Error JS: $e',
        );
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 500),
      );
    }

    debugPrint(
      '[SoundNeed YouTube] NO SE ENCONTRARON RESULTADOS',
    );

    return const [];
  }

  Future<bool> _waitForPage() async {
    final completer = _pageLoaded;

    if (completer == null) {
      return false;
    }

    try {
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint(
            '[SoundNeed YouTube] Timeout esperando página.',
          );

          return false;
        },
      );
    } catch (e) {
      debugPrint(
        '[SoundNeed YouTube] Error esperando página: $e',
      );

      return false;
    }
  }

  String _normalizeJavaScriptResult(
    Object? raw,
  ) {
    if (raw == null) {
      return '';
    }

    var value = raw.toString();

    if (value.startsWith('"') &&
        value.endsWith('"')) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is String) {
          value = decoded;
        }
      } catch (_) {}
    }

    return value;
  }

  static const String _extractJavaScript = r'''
(function () {

  var result = {
    url: String(window.location.href || ''),
    title: String(document.title || ''),
    ytInitialData: typeof window.ytInitialData !== 'undefined',
    ytInitialPlayerResponse:
      typeof window.ytInitialPlayerResponse !== 'undefined',
    bodyLength: document.body
      ? document.body.innerText.length
      : 0,
    htmlLength: document.documentElement
      ? document.documentElement.outerHTML.length
      : 0,
    bodyText: document.body
      ? document.body.innerText.substring(0, 3000)
      : ''
  };

  try {
    var html =
      document.documentElement.outerHTML || '';

    result.videoRendererCount =
      (html.match(/videoRenderer/g) || []).length;

    result.videoIdCount =
      (html.match(/videoId/g) || []).length;

  } catch (e) {
    result.debugError = String(e);
  }

  return JSON.stringify(result);

})();
''';
}import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  factory YouTubeSearchResult.fromMap(Map<String, dynamic> map) {
    final videoId = map['video_id']?.toString() ?? '';

    return YouTubeSearchResult(
      videoId: videoId,
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      duration: int.tryParse(map['duration']?.toString() ?? '') ?? 0,
      thumbnail: map['thumbnail']?.toString() ?? '',
      url: 'https://www.youtube.com/watch?v=$videoId',
    );
  }
}

class YouTubeSearchService {
  YouTubeSearchService._();

  static final YouTubeSearchService instance = YouTubeSearchService._();

  WebViewController? _controller;

  Completer<bool>? _pageLoaded;

  WebViewController get controller {
    if (_controller == null) {
      throw StateError('YouTubeSearchService todavía no fue inicializado.');
    }

    return _controller!;
  }

  bool get isInitialized => _controller != null;

  Future<void> initialize() async {
    if (_controller != null) {
      return;
    }

    final controller = WebViewController();

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    await controller.setBackgroundColor(const Color(0xFF000000));

    // User-Agent de escritorio: YouTube móvil usa otra estructura de datos.
    await controller.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          debugPrint('[SoundNeed YouTube] PAGE STARTED: $url');
        },
        onPageFinished: (url) {
          debugPrint('[SoundNeed YouTube] PAGE FINISHED: $url');

          if (_pageLoaded != null && !_pageLoaded!.isCompleted) {
            _pageLoaded!.complete(true);
          }
        },
        onWebResourceError: (error) {
          debugPrint(
            '[SoundNeed YouTube] WEB ERROR: '
            '${error.errorCode} ${error.description}',
          );
          // ERR_CACHE_MISS no significa que la página completa falló.
          // Esperamos a onPageFinished.
        },
      ),
    );

    _controller = controller;
  }

  Future<List<YouTubeSearchResult>> search(String query) async {
    query = query.trim();

    if (query.isEmpty) {
      return const [];
    }

    await initialize();

    final controller = _controller!;

    final encoded = Uri.encodeQueryComponent(query);

    final url = 'https://www.youtube.com/results?search_query=$encoded';

    debugPrint('');
    debugPrint('[SoundNeed YouTube] ============================');
    debugPrint('[SoundNeed YouTube] BUSCANDO: $query');
    debugPrint('[SoundNeed YouTube] URL: $url');

    final pageLoaded = Completer<bool>();
    _pageLoaded = pageLoaded;

    await controller.loadRequest(Uri.parse(url));

    bool loaded = false;

    try {
      loaded = await pageLoaded.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[SoundNeed YouTube] TIMEOUT esperando página: $e');
    }

    if (!loaded) {
      debugPrint('[SoundNeed YouTube] La página no terminó de cargar.');
      return const [];
    }

    // Damos tiempo a YouTube para construir su estado.
    await Future<void>.delayed(const Duration(seconds: 2));

    for (int attempt = 1; attempt <= 15; attempt++) {
      debugPrint('[SoundNeed YouTube] Extracción $attempt/15');

      try {
        final raw = await controller.runJavaScriptReturningResult(
          _extractJavaScript,
        );

        final normalized = _normalizeJavaScriptResult(raw);

        if (normalized.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final decoded = jsonDecode(normalized);

        if (decoded is! Map) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        debugPrint(
          '[SoundNeed YouTube] hasData: ${decoded['hasData']} '
          'count: ${decoded['count']}',
        );

        final items = decoded['items'];

        if (items is! List) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final results = items
            .whereType<Map>()
            .map(
              (item) => YouTubeSearchResult.fromMap(
                Map<String, dynamic>.from(item),
              ),
            )
            .where(
              (result) => result.videoId.isNotEmpty && result.title.isNotEmpty,
            )
            .toList();

        if (results.isNotEmpty) {
          debugPrint('[SoundNeed YouTube] RESULTADOS: ${results.length}');
          return results;
        }
      } catch (e) {
        debugPrint('[SoundNeed YouTube] Error JS: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('[SoundNeed YouTube] NO SE ENCONTRARON RESULTADOS');

    return const [];
  }

  String _normalizeJavaScriptResult(Object? raw) {
    if (raw == null) {
      return '';
    }

    var value = raw.toString();

    // En Android el resultado llega como string JSON con comillas
    // y caracteres escapados; lo decodificamos una vez.
    if (value.startsWith('"') && value.endsWith('"')) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is String) {
          value = decoded;
        }
      } catch (_) {}
    }

    return value;
  }

  static const String _extractJavaScript = r'''
(function () {
  function textOf(o) {
    if (!o) return '';
    if (o.simpleText) return o.simpleText;
    if (o.runs) return o.runs.map(function (r) { return r.text; }).join('');
    return '';
  }

  function toSeconds(s) {
    if (!s) return 0;
    var parts = s.split(':');
    var t = 0;
    for (var i = 0; i < parts.length; i++) {
      t = t * 60 + (parseInt(parts[i], 10) || 0);
    }
    return t;
  }

  var data = window.ytInitialData;

  // Fallback: leerlo desde los <script>
  if (!data) {
    var scripts = document.getElementsByTagName('script');
    for (var i = 0; i < scripts.length; i++) {
      var txt = scripts[i].textContent || '';
      var idx = txt.indexOf('ytInitialData');
      if (idx !== -1) {
        var start = txt.indexOf('{', idx);
        var end = txt.lastIndexOf('}');
        if (start !== -1 && end > start) {
          try {
            data = JSON.parse(txt.substring(start, end + 1));
            break;
          } catch (e) {}
        }
      }
    }
  }

  var items = [];

  if (data) {
    var stack = [data];
    while (stack.length && items.length < 30) {
      var node = stack.pop();
      if (!node || typeof node !== 'object') continue;

      if (node.videoRenderer && node.videoRenderer.videoId) {
        var v = node.videoRenderer;
        var thumbs = (v.thumbnail && v.thumbnail.thumbnails) || [];
        items.push({
          video_id: v.videoId,
          title: textOf(v.title),
          artist: textOf(v.ownerText || v.longBylineText),
          duration: toSeconds(textOf(v.lengthText)),
          thumbnail: thumbs.length ? thumbs[thumbs.length - 1].url : ''
        });
        continue;
      }

      for (var k in node) {
        if (node[k] && typeof node[k] === 'object') stack.push(node[k]);
      }
    }
  }

  return JSON.stringify({
    hasData: !!data,
    count: items.length,
    items: items
  });
})();
''';
}