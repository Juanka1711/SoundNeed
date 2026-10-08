import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Normalized lyrics used by the existing SoundNeed player.
class LyricsData {
  final String? plainLyrics;
  final String? syncedLyrics;
  final List<LyricLine> lines;

  /// Duration reported by LRCLIB for the selected lyrics record.
  final Duration? sourceDuration;

  /// Current audio duration - LRCLIB duration.
  final Duration? durationDifference;

  /// Offset automatically applied to lyric timestamps.
  ///
  /// Positive = lyrics are moved forward.
  /// Negative = lyrics are moved backward.
  final Duration syncOffset;

  /// LRCLIB record ID.
  final int? sourceId;

  /// Whether LRCLIB reports word-level timing.
  final bool hasWordSync;

  const LyricsData({
    this.plainLyrics,
    this.syncedLyrics,
    this.lines = const [],
    this.sourceDuration,
    this.durationDifference,
    this.syncOffset = Duration.zero,
    this.sourceId,
    this.hasWordSync = false,
  });

  bool get hasSyncedLyrics => lines.isNotEmpty;

  bool get hasPlainLyrics => plainLyrics?.trim().isNotEmpty ?? false;

  bool get hasLyrics => hasSyncedLyrics || hasPlainLyrics;

  bool get isSyncedToCurrentAudio =>
      hasSyncedLyrics &&
      durationDifference != null &&
      durationDifference!.inMilliseconds.abs() <= 3000;
}

/// A synchronized lyric line.
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});
}

/// LRCLIB lyrics service.
///
/// Strategy:
///
/// 1. Try LRCLIB /api/get with title + artist + album + duration.
/// 2. If the exact duration match fails, query /api/search.
/// 3. Rank the returned candidates by:
///    - title similarity
///    - artist similarity
///    - duration similarity
///    - presence of synchronized lyrics
/// 4. Parse syncedLyrics (LRC).
/// 5. If the selected record has a different duration, calculate a
///    conservative sync offset only when there is reasonable evidence
///    that the difference is caused by a leading intro.
/// 6. Keep the original player-facing API unchanged.
///
/// This means FullPlayer can continue using:
///
/// LyricsService.instance.getLyrics(...)
class LyricsService {
  LyricsService._();

  static final LyricsService instance = LyricsService._();

  static const String _baseUrl = 'https://lrclib.net';

  static final Uri _getEndpoint = Uri.parse('$_baseUrl/api/get');

  static final Uri _searchEndpoint = Uri.parse('$_baseUrl/api/search');

  final http.Client _client = http.Client();

  /// Store only successful lyrics as cache values; failed requests are retried.
  final Map<String, LyricsData> _cache = {};
  final Map<String, Future<LyricsData?>> _inFlight = {};

  /// Small delay between fallback requests.
  ///
  /// LRCLIB recommends sequential requests with a short delay to avoid
  /// hitting rate limits.
  static const Duration _requestDelay = Duration(milliseconds: 250);

  /// Maximum acceptable difference when considering a search candidate.
  ///
  /// We don't reject candidates solely because of this value; it is used
  /// by the scoring algorithm.
  static const double _maximumDurationDifferenceSeconds = 30.0;

  Future<LyricsData?> getLyrics({
    required String title,
    required String artist,
    String? alternateTitle,
    String? album,
    Duration? duration,
    bool isOnline = false,
  }) {
    final track = title.trim().isNotEmpty
        ? title.trim()
        : (alternateTitle ?? '').trim();

    final performer = artist.trim();

    if (track.isEmpty) {
      return Future.value(null);
    }

    final key = _buildCacheKey(
      title: track,
      artist: performer,
      album: album,
      duration: duration,
    );

    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    late final Future<LyricsData?> future;
    future = _fetchLyrics(
      track: track,
      artist: performer,
      album: album?.trim(),
      duration: duration,
    );
    _inFlight[key] = future;
    future.then(
      (lyrics) {
        if (identical(_inFlight[key], future)) {
          if (lyrics != null) _cache[key] = lyrics;
          _inFlight.remove(key);
        }
      },
      onError: (Object error, StackTrace _) {
        if (identical(_inFlight[key], future)) _inFlight.remove(key);
        debugPrint('[SoundNeed][Lyrics] Request failed: $error');
      },
    );
    return future;
  }

  String _buildCacheKey({
    required String title,
    required String artist,
    required String? album,
    required Duration? duration,
  }) {
    final normalizedTitle = _normalizeForComparison(title);
    final normalizedArtist = _normalizeForComparison(artist);
    final normalizedAlbum = _normalizeForComparison(album ?? '');

    final durationSeconds = duration == null ? 0 : duration.inSeconds;

    return '$normalizedTitle|'
        '$normalizedArtist|'
        '$normalizedAlbum|'
        '$durationSeconds';
  }

  Future<LyricsData?> _fetchLyrics({
    required String track,
    required String artist,
    required String? album,
    required Duration? duration,
  }) async {
    try {
      debugPrint(
        '[SoundNeed][Lyrics] Searching LRCLIB: '
        '"$track" — "$artist" '
        'duration=${duration?.inSeconds}s',
      );

      LyricsRecord? record;

      // Try direct lookups with progressively cleaner metadata. LRCLIB's
      // duration match allows only a narrow tolerance, so repeat candidates
      // without duration before moving to its less reliable search endpoint.
      final titleCandidates = _titleCandidates(track);
      final artistCandidates = _artistCandidates(artist, track);
      final attempts =
          <
            ({String track, String artist, Duration? duration, String? album})
          >[];
      final seenAttempts = <String>{};
      var getEndpointUnavailable = false;

      void addAttempt(
        String lookupTrack,
        String lookupArtist,
        Duration? lookupDuration,
        String? lookupAlbum,
      ) {
        if (lookupTrack.trim().isEmpty || lookupArtist.trim().isEmpty) return;
        final key =
            '${_normalizeForComparison(lookupTrack)}|'
            '${_normalizeForComparison(lookupArtist)}|'
            '${lookupDuration?.inSeconds ?? 0}|'
            '${_normalizeForComparison(lookupAlbum ?? '')}';
        if (seenAttempts.add(key)) {
          attempts.add((
            track: lookupTrack,
            artist: lookupArtist,
            duration: lookupDuration,
            album: lookupAlbum,
          ));
        }
      }

      // First keep the original metadata, then try normalized variants.
      // Supplying duration first is useful when it matches; the same query
      // without duration handles YouTube intros/outros and alternate edits.
      final usableDuration =
          duration != null &&
              duration.inSeconds > 0 &&
              duration.inSeconds <= 3600
          ? duration
          : null;
      final canonicalArtist = _artistFromTitle(track);
      final extractedTitle = titleCandidates.isNotEmpty
          ? titleCandidates.last
          : _cleanVideoTitle(track);
      final cleanTitle = _cleanVideoTitle(track);
      final reliableChannel = _isReliableArtist(artist)
          ? _cleanArtistName(artist)
          : null;
      final extractedArtist = canonicalArtist ??
          reliableChannel ??
          (artistCandidates.isNotEmpty ? artistCandidates.first : '');

      // Prioritize the artist/title parsed from YouTube's video title. A
      // channel name is only used when it looks like a real artist credit.
      addAttempt(extractedTitle, extractedArtist, usableDuration, null);
      addAttempt(extractedTitle, extractedArtist, null, null);
      for (final artistVariant in artistCandidates.skip(2)) {
        if (artistVariant.toLowerCase().contains('feat') ||
            artistVariant.contains(',')) {
          addAttempt(extractedTitle, artistVariant, null, null);
        }
      }
      if (cleanTitle != extractedTitle) {
        addAttempt(cleanTitle, extractedArtist, null, null);
      }
      // One fallback to clean channel metadata, never the noisy full title.
      if (reliableChannel != null && reliableChannel != extractedArtist) {
        addAttempt(cleanTitle, reliableChannel, null, null);
      }
      // Keep the original artist as a last direct lookup only when it is
      // trustworthy and no title-derived artist was available.
      if (canonicalArtist == null && reliableChannel != null) {
        addAttempt(track, reliableChannel, usableDuration, album);
      }
      // Bound requests even for long/ambiguous upload titles.
      if (attempts.length > 5) attempts.removeRange(5, attempts.length);

      for (var index = 0; index < attempts.length; index++) {
        final attempt = attempts[index];
        debugPrint(
          '[SoundNeed][Lyrics] /api/get candidate: '
          '"${attempt.track}" — "${attempt.artist}" '
          'duration=${attempt.duration?.inSeconds ?? 'none'}',
        );
        final lookup = await _getExactMatch(
          track: attempt.track,
          artist: attempt.artist,
          album: attempt.album,
          duration: attempt.duration,
        );
        record = lookup.record;
        if (record != null) break;
        if (lookup.serverUnavailable) {
          getEndpointUnavailable = true;
          break;
        }
        if (index < attempts.length - 1) {
          await Future<void>.delayed(_requestDelay);
        }
      }

      // ---------------------------------------------------------------
      // 2. FALLBACK: /api/search
      // ---------------------------------------------------------------

      if (record == null && !getEndpointUnavailable) {
        await Future.delayed(_requestDelay);

        record = await _searchBestMatch(
          track: extractedTitle,
          artist: extractedArtist,
          album: album,
          duration: duration,
        );
      }

      if (record == null) {
        debugPrint(
          '[SoundNeed][Lyrics] LRCLIB: no suitable match '
          'for "$track" — "$artist"',
        );
        return null;
      }

      debugPrint(
        '[SoundNeed][Lyrics] Selected: '
        'id=${record.id} '
        '"${record.trackName}" — "${record.artistName}" '
        'duration=${record.duration}s '
        'wordSync=${record.hasWordSync}',
      );

      if (record.instrumental) {
        debugPrint('[SoundNeed][Lyrics] LRCLIB says instrumental.');
        return null;
      }

      // ---------------------------------------------------------------
      // 3. PARSE LRC
      // ---------------------------------------------------------------

      final lines = _parseLrc(record.syncedLyrics);

      // If syncedLyrics is missing but plain lyrics exist, we can still
      // show normal lyrics.
      final plain = _cleanPlainLyrics(record.plainLyrics);

      if (lines.isEmpty && plain == null) {
        debugPrint('[SoundNeed][Lyrics] Record contains no usable lyrics.');
        return null;
      }

      // ---------------------------------------------------------------
      // 4. DURATION ANALYSIS
      // ---------------------------------------------------------------

      Duration? sourceDuration;
      Duration? durationDifference;

      if (record.duration > 0) {
        sourceDuration = Duration(
          milliseconds: (record.duration * 1000).round(),
        );

        if (duration != null && duration.inMilliseconds > 0) {
          durationDifference = duration - sourceDuration;
        }
      }

      // ---------------------------------------------------------------
      // 5. CONSERVATIVE SYNC CORRECTION
      // ---------------------------------------------------------------

      final offset = _calculateSafeOffset(
        lines: lines,
        sourceDuration: sourceDuration,
        audioDuration: duration,
      );

      final adjustedLines = offset == Duration.zero
          ? lines
          : _applyOffset(lines, offset);

      if (offset != Duration.zero) {
        debugPrint(
          '[SoundNeed][Lyrics] Automatic sync offset: '
          '${offset.inMilliseconds}ms',
        );
      }

      // ---------------------------------------------------------------
      // 6. NORMALIZED RESULT
      // ---------------------------------------------------------------

      final syncedText = adjustedLines.isEmpty
          ? null
          : adjustedLines.map((line) => line.text).join('\n');

      final result = LyricsData(
        plainLyrics: plain,
        syncedLyrics: syncedText,
        lines: adjustedLines,
        sourceDuration: sourceDuration,
        durationDifference: durationDifference,
        syncOffset: offset,
        sourceId: record.id,
        hasWordSync: record.hasWordSync,
      );

      debugPrint(
        '[SoundNeed][Lyrics] OK '
        'id=${record.id} '
        'lines=${adjustedLines.length} '
        'sourceDuration=${sourceDuration?.inSeconds}s '
        'difference=${durationDifference?.inMilliseconds}ms '
        'offset=${offset.inMilliseconds}ms '
        'wordSync=${record.hasWordSync}',
      );

      return result.hasLyrics ? result : null;
    } on TimeoutException {
      debugPrint('[SoundNeed][Lyrics] LRCLIB timeout for "$track"');
      return null;
    } catch (error, stackTrace) {
      debugPrint('[SoundNeed][Lyrics] Request failed for "$track": $error');

      debugPrint(stackTrace.toString());

      return null;
    }
  }

  // =====================================================================
  // LRCLIB /api/get
  // =====================================================================

  Future<_LyricsLookupResult> _getExactMatch({
    required String track,
    required String artist,
    required String? album,
    required Duration? duration,
  }) async {
    final params = <String, String>{'track_name': track, 'artist_name': artist};

    if (album != null && album.isNotEmpty) {
      params['album_name'] = album;
    }

    if (duration != null &&
        duration.inSeconds > 0 &&
        duration.inSeconds <= 3600) {
      params['duration'] = duration.inSeconds.toString();
    }

    final uri = _getEndpoint.replace(queryParameters: params);

    final response = await _safeGet(uri);

    if (response == null) {
      return const _LyricsLookupResult(serverUnavailable: true);
    }

    if (response.statusCode == 404) {
      debugPrint('[SoundNeed][Lyrics] /api/get: 404');
      return const _LyricsLookupResult();
    }

    if (response.statusCode != 200) {
      debugPrint(
        '[SoundNeed][Lyrics] /api/get HTTP '
        '${response.statusCode}',
      );
      return _LyricsLookupResult(
        serverUnavailable:
            response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    final decoded = _decodeJson(response);

    if (decoded is! Map) {
      return const _LyricsLookupResult();
    }

    return _LyricsLookupResult(
      record: LyricsRecord.fromJson(Map<String, dynamic>.from(decoded)),
    );
  }

  // =====================================================================
  // LRCLIB /api/search
  // =====================================================================

  Future<LyricsRecord?> _searchBestMatch({
    required String track,
    required String artist,
    required String? album,
    required Duration? duration,
  }) async {
    final queries = <Map<String, String>>[];

    // Most precise search.
    queries.add({'track_name': track, 'artist_name': artist});

    // If title has a YouTube-style suffix, this second search can recover
    // the actual track.
    final cleanedTrack = _cleanVideoTitle(track);

    if (_normalizeForComparison(cleanedTrack) !=
        _normalizeForComparison(track)) {
      queries.add({'track_name': cleanedTrack, 'artist_name': artist});
    }

    // Final broad search.
    queries.add({'q': '$track $artist'});

    final allCandidates = <LyricsRecord>[];

    for (final params in queries) {
      final uri = _searchEndpoint.replace(queryParameters: params);

      final response = await _safeGet(uri);

      if (response == null) {
        continue;
      }

      if (response.statusCode != 200) {
        debugPrint(
          '[SoundNeed][Lyrics] /api/search HTTP '
          '${response.statusCode}',
        );
        if (response.statusCode >= 500 || response.statusCode == 429) break;
        continue;
      }

      final decoded = _decodeJson(response);

      if (decoded is! List) {
        continue;
      }

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          final record = LyricsRecord.fromJson(Map<String, dynamic>.from(item));

          if (!_containsSameRecord(allCandidates, record)) {
            allCandidates.add(record);
          }
        } catch (_) {
          // Ignore malformed candidates.
        }
      }

      // Avoid hammering the API.
      await Future.delayed(_requestDelay);
    }

    if (allCandidates.isEmpty) {
      return null;
    }

    final ranked = allCandidates
        .map(
          (record) => _ScoredRecord(
            record: record,
            score: _scoreCandidate(
              record: record,
              track: track,
              artist: artist,
              album: album,
              duration: duration,
            ),
          ),
        )
        .toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));

    for (final candidate in ranked.take(5)) {
      debugPrint(
        '[SoundNeed][Lyrics] Candidate '
        'score=${candidate.score.toStringAsFixed(3)} '
        'id=${candidate.record.id} '
        '"${candidate.record.trackName}" — '
        '"${candidate.record.artistName}" '
        '${candidate.record.duration}s '
        'synced=${candidate.record.syncedLyrics != null}',
      );
    }

    final best = ranked.first;

    // Do not accept terrible matches.
    if (best.score < 0.58) {
      debugPrint(
        '[SoundNeed][Lyrics] Best candidate rejected: '
        'score=${best.score.toStringAsFixed(3)}',
      );
      return null;
    }

    return best.record;
  }

  // =====================================================================
  // HTTP
  // =====================================================================

  Future<http.Response?> _safeGet(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(
              uri,
              headers: const {
                // LRCLIB asks applications to identify themselves.
                'User-Agent': 'SoundNeed/1.0 (Flutter music player)',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (attempt == 0 &&
            (response.statusCode == 503 || response.statusCode == 429)) {
          debugPrint(
            '[SoundNeed][Lyrics] LRCLIB HTTP ${response.statusCode}; '
            'retrying once after a short wait.',
          );
          if (response.statusCode == 429) {
            await _respectRetryAfter(response);
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 700));
          }
          continue;
        }
        return response;
      } on TimeoutException {
        debugPrint('[SoundNeed][Lyrics] HTTP timeout: $uri');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        return null;
      } catch (error) {
        debugPrint('[SoundNeed][Lyrics] HTTP error: $error');
        return null;
      }
    }
    return null;
  }

  dynamic _decodeJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (error) {
      debugPrint('[SoundNeed][Lyrics] JSON decode error: $error');
      return null;
    }
  }

  Future<void> _respectRetryAfter(http.Response response) async {
    final value = response.headers['retry-after'];

    final seconds = int.tryParse(value ?? '');

    if (seconds == null) {
      await Future.delayed(const Duration(seconds: 1));
      return;
    }

    final safeSeconds = math.min(seconds, 10).toInt();

    debugPrint(
      '[SoundNeed][Lyrics] LRCLIB rate limit. '
      'Waiting ${safeSeconds}s.',
    );

    await Future.delayed(Duration(seconds: safeSeconds));
  }

  // =====================================================================
  // CANDIDATE SCORING
  // =====================================================================

  double _scoreCandidate({
    required LyricsRecord record,
    required String track,
    required String artist,
    required String? album,
    required Duration? duration,
  }) {
    final titleScore = _similarity(track, record.trackName);

    final artistScore = _similarity(artist, record.artistName);

    final cleanedTitleScore = _similarity(
      _cleanVideoTitle(track),
      record.trackName,
    );

    final bestTitle = math.max(titleScore, cleanedTitleScore);

    double durationScore = 0.5;

    if (duration != null &&
        duration.inMilliseconds > 0 &&
        record.duration > 0) {
      final difference = (duration.inSeconds - record.duration).abs();

      if (difference <= 2) {
        durationScore = 1.0;
      } else if (difference <= 5) {
        durationScore = 0.9;
      } else if (difference <= 10) {
        durationScore = 0.75;
      } else if (difference <= 20) {
        durationScore = 0.55;
      } else if (difference <= _maximumDurationDifferenceSeconds) {
        durationScore = 0.3;
      } else {
        durationScore = 0.0;
      }
    }

    double albumScore = 0.5;

    if (album != null &&
        album.trim().isNotEmpty &&
        record.albumName.trim().isNotEmpty) {
      albumScore = _similarity(album, record.albumName);
    }

    final syncedBonus =
        record.syncedLyrics != null && record.syncedLyrics!.trim().isNotEmpty
        ? 0.10
        : 0.0;

    final wordSyncBonus = record.hasWordSync ? 0.05 : 0.0;

    final instrumentalPenalty = record.instrumental ? 1.0 : 0.0;

    final score =
        (bestTitle * 0.42) +
        (artistScore * 0.30) +
        (durationScore * 0.18) +
        (albumScore * 0.05) +
        syncedBonus +
        wordSyncBonus -
        instrumentalPenalty;

    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _containsSameRecord(List<LyricsRecord> list, LyricsRecord candidate) {
    return list.any((item) => item.id == candidate.id);
  }

  // =====================================================================
  // SYNC OFFSET
  // =====================================================================

  Duration _calculateSafeOffset({
    required List<LyricLine> lines,
    required Duration? sourceDuration,
    required Duration? audioDuration,
  }) {
    // Duration alone cannot distinguish an intro from an outro or a different
    // edit. Preserve LRCLIB timestamps until there is stronger evidence.
    return Duration.zero;
  }

  List<LyricLine> _applyOffset(List<LyricLine> lines, Duration offset) {
    final result = <LyricLine>[];

    for (final line in lines) {
      var timestamp = line.timestamp + offset;

      // Never allow negative timestamps.
      if (timestamp.isNegative) {
        timestamp = Duration.zero;
      }

      result.add(LyricLine(timestamp: timestamp, text: line.text));
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }

  // =====================================================================
  // LRC PARSER
  // =====================================================================

  List<LyricLine> _parseLrc(String? lrc) {
    if (lrc == null || lrc.trim().isEmpty) {
      return [];
    }

    final lines = <LyricLine>[];

    final sourceLines = lrc.replaceAll('\r\n', '\n').split('\n');

    // Supports:
    //
    // [00:12.34]Text
    // [01:02.345]Text
    // [01:02]Text
    //
    // Also supports multiple timestamps:
    //
    // [00:10.00][00:20.00]Text
    final timestampPattern = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

    for (final rawLine in sourceLines) {
      final matches = timestampPattern.allMatches(rawLine);

      if (matches.isEmpty) {
        continue;
      }

      final text = rawLine.replaceAll(timestampPattern, '').trim();

      if (text.isEmpty) {
        continue;
      }

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '');

        final seconds = int.tryParse(match.group(2) ?? '');

        final fractionRaw = match.group(3);

        if (minutes == null || seconds == null || seconds > 59) {
          continue;
        }

        var milliseconds = 0;

        if (fractionRaw != null) {
          final fraction = int.tryParse(fractionRaw) ?? 0;

          if (fractionRaw.length == 1) {
            milliseconds = fraction * 100;
          } else if (fractionRaw.length == 2) {
            milliseconds = fraction * 10;
          } else {
            milliseconds = fraction.clamp(0, 999).toInt();
          }
        }

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        lines.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Remove exact duplicates.
    final deduplicated = <LyricLine>[];

    for (final line in lines) {
      if (deduplicated.isNotEmpty) {
        final previous = deduplicated.last;

        if (previous.timestamp == line.timestamp &&
            previous.text == line.text) {
          continue;
        }
      }

      deduplicated.add(line);
    }

    return deduplicated;
  }

  // =====================================================================
  // TEXT / TITLE NORMALIZATION
  // =====================================================================

  String? _cleanPlainLyrics(String? value) {
    if (value == null) {
      return null;
    }

    final cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  String _cleanVideoTitle(String title) {
    var value = title.trim();

    // Drop a YouTube suffix after a pipe (for example "| Official Video").
    final pipeSuffix = RegExp(
      r'\s*\|\s*(?:official|music|lyric|lyrics|visualizer|audio|video|4k|hd).*$',
      caseSensitive: false,
    );
    value = value.replaceAll(pipeSuffix, '');

    // Remove bracketed YouTube labels, including "Lyric Video" variants.
    value = value.replaceAll(
      RegExp(
        r'\s*[\(\[][^\)\]]*'
        r'(official|music\s*video|video|lyrics?|audio|visualizer|4k|hd|topic|'
        r'rip|slowed|reverb|sped\s*up|nightcore)'
        r'[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );

    // Remove bracketless remix decorations and production/channel credits.
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-–—]\s*)?(?:prod\.?|produced\s+by|production\s+by)\s+.+$',
        caseSensitive: false,
      ),
      '',
    );

    // Remove common unbracketed suffixes and featured-artist annotations.
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-–—|]\s*)?(?:official\s+)?(?:music\s+)?'
        r'(?:lyric\s+video|lyrics?\s+video|music\s+video|official\s+video|'
        r'video|official\s+audio|audio|visualizer|4k|hd|topic)\s*$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(
      RegExp(r'\s+(?:ft\.?|feat\.?|featuring)\s+.+$', caseSensitive: false),
      '',
    );

    return value.trim();
  }

  List<String> _titleCandidates(String title) {
    final result = <String>[];
    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isNotEmpty &&
          !result.any(
            (item) =>
                _normalizeForComparison(item) ==
                _normalizeForComparison(cleaned),
          )) {
        result.add(cleaned);
      }
    }

    add(title);
    final cleaned = _cleanVideoTitle(title);
    add(cleaned);

    final split = RegExp(r'^\s*(.+?)\s+[-–—]\s+(.+?)\s*$').firstMatch(cleaned);
    if (split != null) {
      final prefix = split.group(1)!.trim();
      final rightSide = split.group(2)!.trim();
      if (_looksLikeArtistCredit(prefix)) {
        if (rightSide.startsWith('@') ||
            RegExp(
              r'^(?:prod\.?|produced\s+by)',
              caseSensitive: false,
            ).hasMatch(rightSide)) {
          // Some upload titles have no track name after the artist; keep the
          // artist itself as a last-resort track candidate.
          add(prefix);
        } else {
          add(_cleanVideoTitle(rightSide));
        }
      }
    }
    return result;
  }

  List<String> _artistCandidates(String artist, String title) {
    final result = <String>[];
    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isNotEmpty &&
          !result.any(
            (item) =>
                _normalizeForComparison(item) ==
                _normalizeForComparison(cleaned),
          )) {
        result.add(cleaned);
      }
    }

    add(artist);
    add(_cleanArtistName(artist));

    final split = RegExp(r'^\s*(.+?)\s+[-–—]\s+(.+?)\s*$').firstMatch(title);
    if (split != null) {
      final titleArtist = split.group(1)!.trim();
      if (_looksLikeArtistCredit(titleArtist)) {
        add(_cleanArtistName(titleArtist));
      }
    }

    // A YouTube channel named "llllllll" or "ArtistMusic" is not reliable.
    // Put a recognizable artist parsed from the video title after metadata
    // variants so direct lookups try it as their strongest candidate.
    final canonical = _artistFromTitle(title);
    if (canonical != null) {
      if (result.length > 1) result.remove(canonical);
      add(canonical);

      final featured = RegExp(
        r'\b(?:ft\.?|feat\.?|featuring)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(title)?.group(1)?.trim();
      if (featured != null && featured.isNotEmpty) {
        add('$canonical feat. $featured');
        add('$canonical, $featured');
      }
    }
    return result;
  }

  String? _artistFromTitle(String title) {
    final split = RegExp(r'^\s*(.+?)\s+[-–—]\s+(.+?)\s*$').firstMatch(title);
    final prefix = split?.group(1)?.trim();
    if (prefix == null || !_looksLikeArtistCredit(prefix)) return null;
    return _cleanArtistName(prefix);
  }

  bool _looksLikeArtistCredit(String value) {
    final normalized = value.trim();
    if (normalized.length < 2 || normalized.length > 48) return false;
    if (RegExp(
      r'^(?:official|audio|video|lyrics?|topic|prod\.?|produced\s+by)$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return false;
    }
    return RegExp(r'[\p{L}]', unicode: true).hasMatch(normalized);
  }

  bool _isReliableArtist(String value) {
    final candidate = value.trim();
    if (!_looksLikeArtistCredit(candidate)) return false;
    final compact = candidate.replaceAll(
      RegExp(r'[^\p{L}\p{N}]', unicode: true),
      '',
    );
    if (compact.isEmpty) return false;
    // Common YouTube channel labels and autogenerated uploader names are not
    // song-artist metadata. Prefer an artist parsed from "Artist - Title".
    if (RegExp(r'^(.)\1{4,}$', caseSensitive: false).hasMatch(compact)) {
      return false;
    }
    if (RegExp(r'(?:music|official|channel)$', caseSensitive: false)
        .hasMatch(compact)) {
      return false;
    }
    if (RegExp(r'\d{2,}$').hasMatch(compact)) return false;
    return true;
  }

  String _cleanArtistName(String artist) {
    var value = artist.trim();
    value = value.replaceAll(
      RegExp(r'\s*[-–—]\s*topic$', caseSensitive: false),
      '',
    );
    value = value.replaceAll(
      RegExp(
        r'(?:official\s*)?(?:music\s*)?(?:vevo|channel)$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(
      RegExp(r'(?:official\s*)?music$', caseSensitive: false),
      '',
    );
    value = value.replaceAll(RegExp(r'\s+official$', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*[@#]+\s*'), ' ');
    value = value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );
    return value.trim();
  }

  String _normalizeForComparison(String value) {
    var normalized = value.toLowerCase();

    // Normalize common apostrophes.
    normalized = normalized
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('´', "'");

    // Remove accents.
    normalized = normalized
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');

    // Remove YouTube decorations.
    normalized = _cleanVideoTitle(normalized);

    // Common separators become spaces.
    normalized = normalized.replaceAll(RegExp(r'[-_/|•·]+'), ' ');

    // Remove punctuation.
    normalized = normalized.replaceAll(
      RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
      ' ',
    );

    // Normalize whitespace.
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');

    return normalized.trim();
  }

  // =====================================================================
  // STRING SIMILARITY
  // =====================================================================

  double _similarity(String a, String b) {
    final left = _normalizeForComparison(a);

    final right = _normalizeForComparison(b);

    if (left.isEmpty || right.isEmpty) {
      return 0.0;
    }

    if (left == right) {
      return 1.0;
    }

    if (left.contains(right) || right.contains(left)) {
      final shorter = math.min(left.length, right.length);

      final longer = math.max(left.length, right.length);

      if (longer > 0) {
        return 0.82 + (shorter / longer) * 0.13;
      }
    }

    final leftWords = left.split(' ').where((e) => e.isNotEmpty).toSet();

    final rightWords = right.split(' ').where((e) => e.isNotEmpty).toSet();

    if (leftWords.isEmpty || rightWords.isEmpty) {
      return 0.0;
    }

    final intersection = leftWords.intersection(rightWords).length;

    final union = leftWords.union(rightWords).length;

    final jaccard = union == 0 ? 0.0 : intersection / union;

    final distance = _levenshtein(left, right);

    final maxLength = math.max(left.length, right.length);

    final editSimilarity = maxLength == 0 ? 0.0 : 1.0 - (distance / maxLength);

    return ((jaccard * 0.55) + (editSimilarity * 0.45))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  int _levenshtein(String a, String b) {
    if (a == b) {
      return 0;
    }

    if (a.isEmpty) {
      return b.length;
    }

    if (b.isEmpty) {
      return a.length;
    }

    var previous = List<int>.generate(b.length + 1, (index) => index);

    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);

      current[0] = i + 1;

      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;

        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }

      previous = current;
    }

    return previous[b.length];
  }
}

// =======================================================================
// LRCLIB RECORD
// =======================================================================

class LyricsRecord {
  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final double duration;
  final bool instrumental;
  final bool hasWordSync;
  final String? plainLyrics;
  final String? syncedLyrics;
  final String? lyricsfile;

  const LyricsRecord({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    required this.hasWordSync,
    required this.plainLyrics,
    required this.syncedLyrics,
    required this.lyricsfile,
  });

  factory LyricsRecord.fromJson(Map<String, dynamic> json) {
    return LyricsRecord(
      id: _parseInt(json['id']),
      trackName:
          json['trackName']?.toString() ?? json['name']?.toString() ?? '',
      artistName: json['artistName']?.toString() ?? '',
      albumName: json['albumName']?.toString() ?? '',
      duration: _parseDouble(json['duration']),
      instrumental: json['instrumental'] == true,
      hasWordSync: json['hasWordSync'] == true,
      plainLyrics: json['plainLyrics']?.toString(),
      syncedLyrics: json['syncedLyrics']?.toString(),
      lyricsfile: json['lyricsfile']?.toString(),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

class _LyricsLookupResult {
  final LyricsRecord? record;
  final bool serverUnavailable;

  const _LyricsLookupResult({this.record, this.serverUnavailable = false});
}

// =======================================================================
// SEARCH RESULT
// =======================================================================

class _ScoredRecord {
  final LyricsRecord record;
  final double score;

  const _ScoredRecord({required this.record, required this.score});
}
