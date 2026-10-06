import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LyricsData {
  final String? plainLyrics;
  final String? syncedLyrics;
  final List<LyricLine> lines;

  /// Duración de la canción que LRCLIB asocia con estas letras.
  final Duration? sourceDuration;

  /// Diferencia entre la duración del audio actual y la de LRCLIB.
  final Duration? durationDifference;

  const LyricsData({
    this.plainLyrics,
    this.syncedLyrics,
    this.lines = const [],
    this.sourceDuration,
    this.durationDifference,
  });

  bool get hasSyncedLyrics => lines.isNotEmpty;

  bool get hasPlainLyrics =>
      plainLyrics?.trim().isNotEmpty ?? false;

  bool get hasLyrics =>
      hasSyncedLyrics || hasPlainLyrics;

  /// Consideramos que las marcas LRC corresponden al audio actual
  /// cuando la diferencia de duración es suficientemente pequeña.
  bool get isSyncedToCurrentAudio {
    if (!hasSyncedLyrics || durationDifference == null) {
      return false;
    }

    return durationDifference!.inMilliseconds.abs() <= 3000;
  }
}

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });
}

class _AiSongInfo {
  final String songTitle;
  final String artist;

  const _AiSongInfo({
    required this.songTitle,
    required this.artist,
  });
}

class _ScoredLyrics {
  final LyricsData lyrics;
  final double score;
  final double durationDifferenceSeconds;
  final Map<String, dynamic> record;

  const _ScoredLyrics({
    required this.lyrics,
    required this.score,
    required this.durationDifferenceSeconds,
    required this.record,
  });
}

class LyricsService {
  LyricsService._();

  static final LyricsService instance = LyricsService._();

  final http.Client _client = http.Client();

  // ============================================================
  // GROQ
  // ============================================================

  //
  // API key de Groq para extracción de nombres de canciones con IA
  //
  // Ejecuta Flutter con:
  //
  // flutter run --dart-define=GROQ_API_KEY=TU_API_KEY
  //
  // O configura GROQ_API_KEY en el build de tu aplicación.
  //
  static const String _groqApiKey =
      String.fromEnvironment('GROQ_API_KEY');

  static const String _groqModel = 'openai/gpt-oss-120b';

  // ============================================================
  // LRCLIB
  // ============================================================

  static const String _lrclibUserAgent =
      'SoundNeed/1.0 (Music Player)';

  // Evita golpear LRCLIB demasiado rápido.
  DateTime? _lastLrcRequest;

  // ============================================================
  // CACHE DE EXTRACCIÓN IA
  // ============================================================

  final Map<String, _AiSongInfo?> _aiCache = {};

  // ============================================================
  // MÉTODO PRINCIPAL
  // ============================================================

  Future<LyricsData?> getLyrics({
    required String title,
    required String artist,
    String? alternateTitle,
    String? album,
    Duration? duration,
    bool isOnline = false,
  }) async {
    final originalTitle = title.trim();

    if (originalTitle.isEmpty) {
      return null;
    }

    _log('START title="$title" artist="$artist" online=$isOnline '
        'duration=${duration?.inSeconds}s alternate="$alternateTitle"');

    try {
      // ----------------------------------------------------------
      // 1. OBTENER NOMBRE REAL DE LA CANCIÓN
      // ----------------------------------------------------------

      _AiSongInfo? aiSong;

      if (isOnline) {
        _log('Groq extraction: starting');
        aiSong = await _extractSongWithAI(
          originalTitle,
          artist: artist,
        );
        _log(aiSong == null
            ? 'Groq extraction unavailable; using fallback titles'
            : 'Groq extracted title="${aiSong.songTitle}" artist="${aiSong.artist}"');
      }

      // ----------------------------------------------------------
      // 2. GENERAR CANDIDATOS
      // ----------------------------------------------------------

      final candidates = <String>[];

      void addCandidate(String? value) {
        if (value == null) return;

        final cleaned = value.trim();

        if (cleaned.isEmpty) return;

        final normalized = _normalize(cleaned);

        if (normalized.isEmpty) return;

        if (!candidates.any(
          (existing) => _normalize(existing) == normalized,
        )) {
          candidates.add(cleaned);
        }
      }

      // La respuesta de la IA tiene prioridad.
      if (aiSong != null) {
        addCandidate(aiSong.songTitle);
      }

      // Título proporcionado por el reproductor.
      addCandidate(_cleanTitle(originalTitle));

      // Si existe título alternativo.
      if (alternateTitle != null) {
        addCandidate(_cleanTitle(alternateTitle));
      }

      // Extraer manualmente el lado derecho de:
      //
      // ARTISTA - CANCIÓN
      //
      // Esto funciona como respaldo si la IA no está disponible.
      for (final value in [
        originalTitle,
        alternateTitle ?? '',
      ]) {
        final extracted = _extractSongTitleLocally(value);

        if (extracted != null) {
          addCandidate(extracted);
        }
      }

      if (candidates.isEmpty) {
        _log('No usable title candidates');
        return null;
      }
      _log('LRCLIB search candidates: ${candidates.join(' | ')}');

      // ----------------------------------------------------------
      // 3. BUSCAR EN LRCLIB
      // ----------------------------------------------------------

      _ScoredLyrics? bestSynced;
      _ScoredLyrics? bestPlain;
      final scoredById = <String, _ScoredLyrics>{};

      for (final candidate in candidates) {
        final records = await _searchLrcLib(
          candidate,
        );
        _log('LRCLIB query "$candidate": ${records.length} result(s)');

        for (final record in records) {
          final scored = _scoreRecord(
            record: record,
            requestedTitle: candidate,
            requestedArtist: aiSong?.artist.isNotEmpty == true
                ? aiSong!.artist
                : artist,
            requestedDuration: duration,
          );

          if (scored == null) {
            _log('Candidate rejected: ${record['trackName']} — ${record['artistName']}');
            continue;
          }

          final recordId = record['id']?.toString();
          if (recordId != null && recordId.isNotEmpty) {
            final previous = scoredById[recordId];
            if (previous == null || scored.score > previous.score) {
              scoredById[recordId] = scored;
            }
          }
          final lyrics = scored.lyrics;
          _log('Candidate id=${record['id']} "${record['trackName']}" — '
              '"${record['artistName']}" duration=${record['duration']}s '
              'synced=${lyrics.hasSyncedLyrics} score=${scored.score.toStringAsFixed(1)} '
              'durationDelta=${scored.durationDifferenceSeconds.toStringAsFixed(2)}s');

          if (lyrics.hasSyncedLyrics) {
            if (bestSynced == null ||
                scored.score > bestSynced.score) {
              bestSynced = scored;
            }
          } else if (lyrics.hasPlainLyrics) {
            if (bestPlain == null ||
                scored.score > bestPlain.score) {
              bestPlain = scored;
            }
          }
        }
      }

      // ----------------------------------------------------------
      // 4. GROQ ELIGE SOLO ENTRE LOS IDs DEVUELTOS POR LRCLIB
      // ----------------------------------------------------------

      if (isOnline && scoredById.isNotEmpty) {
        final candidatesForSelection = _prioritizeSyncedCandidates(
          scoredById.values.toList(),
        );
        final selectedId = await _selectLyricsWithAI(
          songTitle: aiSong?.songTitle ?? candidates.first,
          artist: aiSong?.artist.isNotEmpty == true ? aiSong!.artist : artist,
          audioDuration: duration,
          candidates: candidatesForSelection,
        );
        if (selectedId != null) {
          _ScoredLyrics? selected;
          for (final candidate in candidatesForSelection) {
            if (candidate.record['id']?.toString() == selectedId) {
              selected = candidate;
              break;
            }
          }
          if (selected == null) {
            _log('Groq selection rejected: id=$selectedId is absent from LRCLIB results');
          } else {
            _log('Groq selected LRCLIB id=$selectedId '
                '"${selected.record['trackName']}" — "${selected.record['artistName']}" '
                'durationDelta=${selected.durationDifferenceSeconds.toStringAsFixed(2)}s '
                'synced=${selected.lyrics.hasSyncedLyrics}');
            return selected.lyrics;
          }
        }
      }

      _log('Using deterministic fallback selection');

      if (bestSynced != null) {
        _log('Selected deterministic synced lyrics: id=${bestSynced.record['id']}');
        return bestSynced.lyrics;
      }

      if (bestPlain != null) {
        _log('Selected deterministic plain lyrics: id=${bestPlain.record['id']}');
        return bestPlain.lyrics;
      }

      _log('No lyrics found');
      return null;
    } catch (e, stack) {
      _log('ERROR: $e\n$stack');
      return null;
    }
  }

  // ============================================================
  // GROQ: EXTRAER NOMBRE DE LA CANCIÓN
  // ============================================================

  Future<_AiSongInfo?> _extractSongWithAI(
    String youtubeTitle, {
    String? artist,
  }) async {
    if (_groqApiKey.trim().isEmpty) {
      // Si no hay API key, continuamos con el extractor local.
      _log('Groq extraction skipped: GROQ_API_KEY is not configured');
      return null;
    }

    final cacheKey =
        '${youtubeTitle.trim().toLowerCase()}|${artist?.trim().toLowerCase() ?? ''}';

    if (_aiCache.containsKey(cacheKey)) {
      _log('Groq extraction cache hit');
      return _aiCache[cacheKey];
    }

    try {
      final prompt = '''
You are the song-title extraction engine for a music player.

Analyze this YouTube music video title and identify the actual SONG TITLE.

Do NOT return:
- "Lyrics"
- "Letra"
- "Official Video"
- "Official Music Video"
- "Audio"
- "Visualizer"
- "Video"
- "CantoYo Video Lyrics"
- channel names
- YouTube metadata
- emojis
- hashtags
- promotional text

If the title has the common format:

ARTIST - SONG TITLE

return only the SONG TITLE.

Examples:

"Kris R X GEEZYDEE - TUKI TUKI (Lyrics) [CantoYo Video Lyrics]"
=> "TUKI TUKI"

"Kris R - TUKI TUKI | Official Video"
=> "TUKI TUKI"

"TUKI TUKI - Kris R. ft. GeezyDee (Letra)"
=> "TUKI TUKI"

Do not invent information.

Return ONLY valid JSON using exactly this structure:

{
  "song_title": "...",
  "artist": "..."
}

YouTube title:
$youtubeTitle

Known artist, if available:
${artist?.trim() ?? ''}
''';

      final response = await _client
          .post(
            Uri.https(
              'api.groq.com',
              '/openai/v1/chat/completions',
            ),
            headers: {
              'Authorization': 'Bearer $_groqApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _groqModel,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You extract song titles from music video titles. '
                      'Return only valid JSON.',
                },
                {
                  'role': 'user',
                  'content': prompt,
                },
              ],
              'temperature': 0,
              // Allow enough room for the reasoning model to finish its JSON.
              'max_completion_tokens': 1024,
              'top_p': 1,
              'reasoning_effort': 'low',
              'stream': false,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        _log('Groq extraction HTTP ${response.statusCode}: ${response.body}');
        _aiCache[cacheKey] = null;
        return null;
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        _aiCache[cacheKey] = null;
        return null;
      }

      final choices = decoded['choices'];

      if (choices is! List || choices.isEmpty) {
        _aiCache[cacheKey] = null;
        return null;
      }

      final firstChoice = choices.first;

      if (firstChoice is! Map<String, dynamic>) {
        _aiCache[cacheKey] = null;
        return null;
      }

      final message = firstChoice['message'];

      if (message is! Map<String, dynamic>) {
        _aiCache[cacheKey] = null;
        return null;
      }

      var content = message['content']?.toString() ?? '';

      content = content.trim();

      if (content.isEmpty) {
        _aiCache[cacheKey] = null;
        return null;
      }

      // Algunos modelos pueden devolver:
      //
      // ```json
      // {...}
      // ```
      //
      // Lo limpiamos antes de hacer jsonDecode.
      content = _extractJson(content);

      final json = jsonDecode(content);

      if (json is! Map<String, dynamic>) {
        _aiCache[cacheKey] = null;
        return null;
      }

      final songTitle =
          json['song_title']?.toString().trim() ?? '';

      final extractedArtist =
          json['artist']?.toString().trim() ?? '';

      if (songTitle.isEmpty) {
        _aiCache[cacheKey] = null;
        return null;
      }

      // Seguridad: si la IA devolviera basura de YouTube,
      // hacemos una limpieza final.
      final cleanSongTitle = _cleanTitle(songTitle);

      if (cleanSongTitle.isEmpty) {
        _aiCache[cacheKey] = null;
        return null;
      }

      final result = _AiSongInfo(
        songTitle: cleanSongTitle,
        artist: extractedArtist,
      );

      _aiCache[cacheKey] = result;

      return result;
    } catch (error) {
      _log('Groq extraction error: $error');
      _aiCache[cacheKey] = null;
      return null;
    }
  }

  // ============================================================
  // GROQ: ELEGIR SOLO UN ID QUE LRCLIB YA DEVOLVIÓ
  // ============================================================

  Future<String?> _selectLyricsWithAI({
    required String songTitle,
    required String artist,
    required Duration? audioDuration,
    required List<_ScoredLyrics> candidates,
  }) async {
    if (_groqApiKey.trim().isEmpty) {
      _log('Groq selection skipped: GROQ_API_KEY is not configured');
      return null;
    }

    final eligible = candidates.where((candidate) {
      final id = candidate.record['id']?.toString();
      return id != null && id.isNotEmpty && candidate.lyrics.hasLyrics;
    }).toList()
      ..sort((a, b) {
        final durationOrder = a.durationDifferenceSeconds
            .compareTo(b.durationDifferenceSeconds);
        return durationOrder != 0
            ? durationOrder
            : b.score.compareTo(a.score);
      });
    if (eligible.length > 9) {
      eligible.removeRange(9, eligible.length);
    }
    if (eligible.isEmpty) {
      _log('Groq selection skipped: no eligible LRCLIB IDs');
      return null;
    }

    final payload = eligible.map((candidate) {
      final record = candidate.record;
      return {
        'id': record['id'],
        'trackName': record['trackName'],
        'artistName': record['artistName'],
        'duration': record['duration'],
        'hasSyncedLyrics': candidate.lyrics.hasSyncedLyrics,
        'hasPlainLyrics': candidate.lyrics.hasPlainLyrics,
        'durationDifferenceSeconds':
            candidate.durationDifferenceSeconds == 999999
                ? null
                : candidate.durationDifferenceSeconds,
        'localScore': candidate.score,
      };
    }).toList();

    final prompt = '''
Compare the video's duration with the duration of every supplied LRCLIB result.
Choose the result with the SMALLEST absolute duration difference, as long as
its title is a plausible match for the song. Duration closeness is the primary
choice criterion. When two results have the same duration (or differ by no
more than 1 second), prefer the one with synced lyrics, then use artist/title
to resolve the tie. Never choose a clearly longer-duration result just because
it has synced lyrics. You may select ONLY an id from the supplied results.
Never invent an id. If none has a plausible title match, return null.

Return only JSON: {"selected_id": 123} or {"selected_id": null}.

Audio title: $songTitle
Audio artist: $artist
Audio duration seconds: ${audioDuration?.inMilliseconds == null ? 'unknown' : audioDuration!.inMilliseconds / 1000}
LRCLIB results: ${jsonEncode(payload)}
''';

    try {
      _log('Groq selection: sending ${eligible.length} LRCLIB candidate(s) '
          '(maximum 9), ordered by closest duration');
      final response = await _client
          .post(
            Uri.https('api.groq.com', '/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_groqApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _groqModel,
              'messages': [
                {
                  'role': 'system',
                  'content': 'Select only among supplied LRCLIB IDs. Return JSON.',
                },
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0,
              // gpt-oss counts reasoning tokens toward this limit. 150 often
              // ends before the final JSON (finish_reason=length).
              'max_completion_tokens': 1024,
              'reasoning_effort': 'low',
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log('Groq selection HTTP ${response.statusCode}: ${response.body}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['choices'] is! List) {
        _log('Groq selection returned an invalid response envelope');
        return null;
      }
      final choices = decoded['choices'] as List;
      if (choices.isEmpty || choices.first is! Map) {
        _log('Groq selection returned no choices');
        return null;
      }
      final choice = choices.first as Map;
      final message = choice['message'];
      final content = message is Map
          ? message['content']?.toString().trim() ?? ''
          : '';
      if (content.isEmpty) {
        _log('Groq selection returned empty content '
            '(finish_reason=${choice['finish_reason']})');
        return null;
      }

      final cleanedContent = _extractJson(content);
      dynamic selection;
      try {
        selection = jsonDecode(cleanedContent);
      } on FormatException {
        _log('Groq selection returned non-JSON content: $content');
        return null;
      }
      if (selection is! Map || selection['selected_id'] == null) {
        _log('Groq selection response: no candidate selected');
        return null;
      }
      final selectedId = selection['selected_id'].toString();
      _log('Groq selection response: selected_id=$selectedId');
      return selectedId;
    } catch (error) {
      _log('Groq selection error: $error');
      return null;
    }
  }

  void _log(String message) {
    debugPrint('[LyricsService] $message');
  }

  List<_ScoredLyrics> _prioritizeSyncedCandidates(
    List<_ScoredLyrics> candidates,
  ) {
    final withKnownDuration = candidates
        .where((candidate) => candidate.durationDifferenceSeconds < 999999)
        .toList();
    if (withKnownDuration.isEmpty) {
      final synced = candidates
          .where((candidate) => candidate.lyrics.hasSyncedLyrics)
          .toList();
      if (synced.isNotEmpty) {
        _log('Synced priority: restricting selection to ${synced.length} '
            'synced candidate(s); audio duration unavailable');
        return synced;
      }
      return candidates;
    }

    final closestDifference = withKnownDuration
        .map((candidate) => candidate.durationDifferenceSeconds)
        .reduce((a, b) => a < b ? a : b);
    final syncedWithinTolerance = candidates.where((candidate) {
      return candidate.lyrics.hasSyncedLyrics &&
          candidate.durationDifferenceSeconds <= closestDifference + 1.0;
    }).toList();

    if (syncedWithinTolerance.isNotEmpty) {
      _log('Synced priority: closest duration delta '
          '${closestDifference.toStringAsFixed(2)}s; sending only synced '
          'candidate(s) within ${(closestDifference + 1).toStringAsFixed(2)}s');
      return syncedWithinTolerance;
    }

    _log('Synced priority: no synced candidate within 1s of the closest '
        'duration; keeping all candidates');
    return candidates;
  }

  String _extractJson(String content) {
    var value = content.trim();

    if (value.startsWith('```')) {
      value = value.replaceFirst(
        RegExp(r'^```(?:json)?\s*'),
        '',
      );

      value = value.replaceFirst(
        RegExp(r'\s*```$'),
        '',
      );
    }

    final firstBrace = value.indexOf('{');
    final lastBrace = value.lastIndexOf('}');

    if (firstBrace >= 0 &&
        lastBrace > firstBrace) {
      value = value.substring(
        firstBrace,
        lastBrace + 1,
      );
    }

    return value.trim();
  }

  // ============================================================
  // LRCLIB SEARCH
  // ============================================================

  Future<List<Map<String, dynamic>>> _searchLrcLib(
    String title,
  ) async {
    try {
      await _respectLrcRateLimit();

      final uri = Uri.https(
        'lrclib.net',
        '/api/search',
        {
          'track_name': title,
        },
      );

      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': _lrclibUserAgent,
            },
          )
          .timeout(
            const Duration(seconds: 12),
          );

      _lastLrcRequest = DateTime.now();

      if (response.statusCode == 429) {
        _log('LRCLIB rate limited the query "$title"');
        final retryAfter =
            response.headers['retry-after'];

        final seconds =
            int.tryParse(retryAfter ?? '');

        if (seconds != null &&
            seconds > 0 &&
            seconds <= 10) {
          await Future<void>.delayed(
            Duration(seconds: seconds),
          );
        }

        return const [];
      }

      if (response.statusCode != 200) {
        _log('LRCLIB HTTP ${response.statusCode} for "$title"');
        return const [];
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (record) => Map<String, dynamic>.from(
              record,
            ),
          )
          .toList();
    } catch (error) {
      _log('LRCLIB search error for "$title": $error');
      return const [];
    }
  }

  Future<void> _respectLrcRateLimit() async {
    final last = _lastLrcRequest;

    if (last == null) {
      return;
    }

    final elapsed =
        DateTime.now().difference(last);

    const minimumDelay =
        Duration(milliseconds: 300);

    if (elapsed < minimumDelay) {
      await Future<void>.delayed(
        minimumDelay - elapsed,
      );
    }
  }

  // ============================================================
  // ELEGIR RESULTADO DE LRCLIB
  // ============================================================

  _ScoredLyrics? _scoreRecord({
    required Map<String, dynamic> record,
    required String requestedTitle,
    required String requestedArtist,
    required Duration? requestedDuration,
  }) {
    final recordTitle =
        record['trackName']?.toString().trim() ?? '';

    if (recordTitle.isEmpty) {
      return null;
    }

    final recordArtist =
        record['artistName']?.toString().trim() ?? '';

    final lyrics =
        _lyricsFromRecord(
      record,
      requestedDuration: requestedDuration,
    );

    if (lyrics == null || !lyrics.hasLyrics) {
      return null;
    }

    final requestedNormalized =
        _normalize(requestedTitle);

    final recordNormalized =
        _normalize(recordTitle);

    if (requestedNormalized.isEmpty ||
        recordNormalized.isEmpty) {
      return null;
    }

    double score = 0;

    // ----------------------------------------------------------
    // TÍTULO
    // ----------------------------------------------------------

    if (recordNormalized == requestedNormalized) {
      score += 100;
    } else if (recordNormalized.contains(
          requestedNormalized,
        ) ||
        requestedNormalized.contains(
          recordNormalized,
        )) {
      score += 75;
    } else {
      final similarity = _titleSimilarity(
        recordNormalized,
        requestedNormalized,
      );

      if (similarity >= 0.90) {
        score += 65;
      } else if (similarity >= 0.75) {
        score += 45;
      } else if (similarity >= 0.60) {
        score += 25;
      } else {
        // El resultado está demasiado alejado
        // del nombre buscado.
        return null;
      }
    }

    // ----------------------------------------------------------
    // DURACIÓN
    // ----------------------------------------------------------

    double durationDifferenceSeconds = 999999;

    if (requestedDuration != null &&
        requestedDuration.inMilliseconds > 0) {
      final rawDuration =
          record['duration'];

      final recordDurationSeconds =
          rawDuration is num
              ? rawDuration.toDouble()
              : double.tryParse(
                  rawDuration?.toString() ?? '',
                );

      if (recordDurationSeconds != null &&
          recordDurationSeconds > 0) {
        durationDifferenceSeconds =
            (recordDurationSeconds -
                    requestedDuration
                            .inMilliseconds /
                        1000)
                .abs();

        // La duración es el criterio más importante
        // después del título.
        if (durationDifferenceSeconds <= 0.5) {
          score += 150;
        } else if (durationDifferenceSeconds <= 1) {
          score += 135;
        } else if (durationDifferenceSeconds <= 2) {
          score += 120;
        } else if (durationDifferenceSeconds <= 3) {
          score += 90;
        } else if (durationDifferenceSeconds <= 5) {
          score += 30;
        } else if (durationDifferenceSeconds <= 10) {
          score -= 20;
        } else if (durationDifferenceSeconds <= 20) {
          score -= 50;
        } else {
          score -= 100;
        }
      }
    }

    // ----------------------------------------------------------
    // ARTISTA
    // ----------------------------------------------------------

    //
    // IMPORTANTE:
    //
    // El artista NO puede descartar el resultado.
    //
    // Solo sirve como desempate.
    //

    final wantedArtist =
        _normalizeArtist(requestedArtist);

    final foundArtist =
        _normalizeArtist(recordArtist);

    if (wantedArtist.isNotEmpty &&
        foundArtist.isNotEmpty) {
      if (wantedArtist == foundArtist) {
        score += 25;
      } else if (_artistSimilarity(
        wantedArtist,
        foundArtist,
      )) {
        score += 15;
      }
    }

    // ----------------------------------------------------------
    // SINCRONIZADAS
    // ----------------------------------------------------------

    if (lyrics.hasSyncedLyrics) {
      score += 20;

      // Si las letras sincronizadas tienen una duración
      // demasiado diferente, no debemos tratarlas como
      // sincronizadas con nuestro audio.
      if (durationDifferenceSeconds <= 3) {
        score += 40;
      } else if (durationDifferenceSeconds <= 5) {
        score += 5;
      }
    } else if (lyrics.hasPlainLyrics) {
      score += 5;
    }

    return _ScoredLyrics(
      lyrics: lyrics,
      score: score,
      durationDifferenceSeconds:
          durationDifferenceSeconds,
      record: Map<String, dynamic>.from(record),
    );
  }

  // ============================================================
  // CONVERTIR RESULTADO LRCLIB A LyricsData
  // ============================================================

  LyricsData? _lyricsFromRecord(
    dynamic record, {
    Duration? requestedDuration,
  }) {
    if (record is! Map) {
      return null;
    }

    final plainLyrics =
        record['plainLyrics']?.toString();

    final syncedLyrics =
        record['syncedLyrics']?.toString();

    final rawDuration =
        record['duration'];

    Duration? sourceDuration;

    final durationSeconds =
        rawDuration is num
            ? rawDuration.toDouble()
            : double.tryParse(
                rawDuration?.toString() ?? '',
              );

    if (durationSeconds != null &&
        durationSeconds > 0) {
      sourceDuration = Duration(
        milliseconds:
            (durationSeconds * 1000).round(),
      );
    }

    Duration? durationDifference;

    if (requestedDuration != null &&
        sourceDuration != null) {
      durationDifference =
          sourceDuration - requestedDuration;

      durationDifference =
          Duration(
        milliseconds:
            durationDifference.inMilliseconds.abs(),
      );
    }

    final lines =
        _parseLrc(syncedLyrics);

    final lyrics = LyricsData(
      plainLyrics: plainLyrics,
      syncedLyrics: syncedLyrics,
      lines: lines,
      sourceDuration: sourceDuration,
      durationDifference:
          durationDifference,
    );

    return lyrics.hasLyrics
        ? lyrics
        : null;
  }

  // ============================================================
  // EXTRACTOR LOCAL DE RESPALDO
  // ============================================================

  String? _extractSongTitleLocally(
    String value,
  ) {
    var cleaned = _cleanTitle(value);

    if (cleaned.isEmpty) {
      return null;
    }

    // Formato:
    //
    // ARTISTA - CANCIÓN
    //
    // Tomamos lo que queda después del primer
    // separador " - ".
    final match = RegExp(
      r'^(.+?)\s+[-–—]\s+(.+)$',
    ).firstMatch(cleaned);

    if (match != null) {
      final left =
          match.group(1)?.trim() ?? '';

      final right =
          match.group(2)?.trim() ?? '';

      if (left.isNotEmpty &&
          right.isNotEmpty) {
        // Si hay otro separador después,
        // eliminamos posibles datos adicionales.
        final candidate =
            right.split(
          RegExp(r'\s+[-–—]\s+'),
        ).first.trim();

        if (candidate.isNotEmpty) {
          return _cleanTitle(candidate);
        }
      }
    }

    return cleaned;
  }

  // ============================================================
  // LIMPIEZA
  // ============================================================

  String _cleanTitle(String value) {
    var cleaned = value.trim();

    if (cleaned.isEmpty) {
      return '';
    }

    // Extensiones.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\.(?:mp3|m4a|aac|flac|wav|ogg|opus|wma)$',
        caseSensitive: false,
      ),
      '',
    );

    // Número inicial:
    //
    // 01 - Song
    // 01. Song
    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^\s*\d{1,3}\s*[-._]\s*',
      ),
      '',
    );

    // Contenido entre corchetes.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*\[(?:'
        r'official|'
        r'lyrics?|'
        r'letra|'
        r'audio|'
        r'video|'
        r'visualizer|'
        r'music\s*video|'
        r'hd|'
        r'4k|'
        r'canto(?:yo)?[^]]*'
        r')[^\]]*\]',
        caseSensitive: false,
      ),
      '',
    );

    // Contenido entre paréntesis relacionado con YouTube.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*\((?:official|lyrics?|letra|audio|video|visualizer|music\s*video|hd|4k[^)]*)\)',
        caseSensitive: false,
      ),
      '',
    );

    // Sufijos comunes.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[-|]\s*(?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?|letra)(?:\s*video)?$',
        caseSensitive: false,
      ),
      '',
    );

    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s+(?:official|lyrics?|letra|audio|video|visualizer)\s*$',
        caseSensitive: false,
      ),
      '',
    );

    return cleaned
        .replaceAll(
          RegExp(r'\s{2,}'),
          ' ',
        )
        .trim();
  }

  // ============================================================
  // NORMALIZACIÓN
  // ============================================================

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'[^a-z0-9áéíóúüñ]+',
            caseSensitive: false,
          ),
          ' ',
        )
        .trim();
  }

  String _normalizeArtist(String value) {
    var normalized = value.toLowerCase();

    normalized = normalized.replaceAll(
      RegExp(r'\b(feat\.?|ft\.?|featuring)\b'),
      ' ',
    );

    normalized = normalized.replaceAll(
      RegExp(r'[-&,x×+]'),
      ' ',
    );

    normalized = normalized.replaceAll(
      RegExp(r'[^a-z0-9áéíóúüñ]+'),
      ' ',
    );

    return normalized
        .replaceAll(
          RegExp(r'\s{2,}'),
          ' ',
        )
        .trim();
  }

  bool _artistSimilarity(
    String first,
    String second,
  ) {
    if (first == second) {
      return true;
    }

    final firstWords = first
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();

    final secondWords = second
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();

    if (firstWords.isEmpty ||
        secondWords.isEmpty) {
      return false;
    }

    final overlap =
        firstWords.intersection(secondWords).length;

    final minimum =
        firstWords.length < secondWords.length
            ? firstWords.length
            : secondWords.length;

    return minimum > 0 &&
        overlap / minimum >= 0.5;
  }

  // ============================================================
  // SIMILITUD DE TÍTULOS
  // ============================================================

  double _titleSimilarity(
    String candidate,
    String requested,
  ) {
    final candidateWords = candidate
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();

    final requestedWords = requested
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();

    if (candidateWords.isEmpty ||
        requestedWords.isEmpty) {
      return 0;
    }

    final overlap =
        candidateWords.intersection(
      requestedWords,
    ).length;

    return overlap / requestedWords.length;
  }

  // ============================================================
  // PARSER LRC
  // ============================================================

  List<LyricLine> _parseLrc(
    String? lrc,
  ) {
    if (lrc == null ||
        lrc.trim().isEmpty) {
      return const [];
    }

    final result = <LyricLine>[];

    final timestampPattern = RegExp(
      r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]',
    );

    for (final rawLine
        in lrc.split(RegExp(r'\r?\n'))) {
      final timestamps =
          timestampPattern
              .allMatches(rawLine)
              .toList();

      if (timestamps.isEmpty) {
        continue;
      }

      final text = rawLine
          .substring(timestamps.last.end)
          .trim();

      if (text.isEmpty) {
        continue;
      }

      for (final match in timestamps) {
        final minutes =
            int.tryParse(
          match.group(1) ?? '',
        );

        final seconds =
            int.tryParse(
          match.group(2) ?? '',
        );

        if (minutes == null ||
            seconds == null) {
          continue;
        }

        var fraction =
            match.group(3) ?? '';

        if (fraction.isNotEmpty) {
          fraction =
              fraction.padRight(3, '0');

          if (fraction.length > 3) {
            fraction =
                fraction.substring(0, 3);
          }
        }

        final milliseconds =
            fraction.isEmpty
                ? 0
                : int.tryParse(fraction) ?? 0;

        result.add(
          LyricLine(
            timestamp: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text: text,
          ),
        );
      }
    }

    result.sort(
      (a, b) =>
          a.timestamp.compareTo(b.timestamp),
    );

    return result;
  }
}
