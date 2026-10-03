import 'dart:convert';

import 'package:http/http.dart' as http;

class LyricsData {
  final String? plainLyrics;
  final String? syncedLyrics;
  final List<LyricLine> lines;

  const LyricsData({
    this.plainLyrics,
    this.syncedLyrics,
    this.lines = const [],
  });

  bool get hasSyncedLyrics => lines.isNotEmpty;
  bool get hasPlainLyrics => plainLyrics?.trim().isNotEmpty ?? false;
  bool get hasLyrics => hasSyncedLyrics || hasPlainLyrics;
}

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});
}

class LyricsService {
  LyricsService._();

  static final LyricsService instance = LyricsService._();
  final http.Client _client = http.Client();

  Future<LyricsData?> getLyrics({
    required String title,
    required String artist,
    String? alternateTitle,
    String? album,
    Duration? duration,
  }) async {
    final titles = <String>{
      _cleanTitle(title),
      if (alternateTitle != null) _cleanTitle(alternateTitle),
    }.where((value) => value.isNotEmpty).toList();
    if (titles.isEmpty) return null;

    final cleanArtist = _cleanArtist(artist);
    final hasArtist = cleanArtist.isNotEmpty && !_isGenericArtist(cleanArtist);
    final cleanAlbum = album?.trim() ?? '';
    LyricsData? exactPlainFallback;
    try {
      if (hasArtist) {
        final exactQuery = <String, String>{
          'track_name': title.trim().isEmpty ? titles.first : title.trim(),
          'artist_name': cleanArtist,
        };
        if (cleanAlbum.isNotEmpty && !_isGenericArtist(cleanAlbum)) {
          exactQuery['album_name'] = cleanAlbum;
        }
        if (duration != null && duration.inSeconds > 0) {
          exactQuery['duration'] =
              (duration.inMilliseconds / 1000).toStringAsFixed(2);
        }
        final response = await _client
            .get(
              Uri.https('lrclib.net', '/api/get', exactQuery),
              headers: const {'User-Agent': 'SoundNeed/1.0'},
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final lyrics = _lyricsFromRecord(
            jsonDecode(utf8.decode(response.bodyBytes)),
          );
          if (lyrics?.hasSyncedLyrics ?? false) return lyrics;
          exactPlainFallback = lyrics;
        }
      }

      LyricsData? bestSyncedMatch;
      var bestSyncedScore = -1;
      LyricsData? bestPlainMatch;
      var bestPlainScore = -1;
      for (final candidateTitle in titles) {
        final searchQueries = <Map<String, String>>[];
        if (hasArtist) {
          searchQueries.add({
            'track_name': candidateTitle,
            'artist_name': cleanArtist,
          });
        }
        // Retry by title alone in case the library has a different artist
        // spelling or incomplete playlist metadata.
        searchQueries.add({'track_name': candidateTitle});

        for (final searchQuery in searchQueries) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final searchResponse = await _client
              .get(
                Uri.https('lrclib.net', '/api/search', searchQuery),
                headers: const {'User-Agent': 'SoundNeed/1.0'},
              )
              .timeout(const Duration(seconds: 12));
          if (searchResponse.statusCode != 200) continue;
          final records = jsonDecode(utf8.decode(searchResponse.bodyBytes));
          if (records is! List) continue;

          for (final record in records) {
          if (record is! Map<String, dynamic>) continue;
          final recordTitle = _normalize(record['trackName']?.toString() ?? '');
          final wantedTitle = _normalize(candidateTitle);
          if (recordTitle.isEmpty ||
              (recordTitle != wantedTitle &&
                  !recordTitle.contains(wantedTitle) &&
                  !wantedTitle.contains(recordTitle) &&
                  _titleSimilarity(recordTitle, wantedTitle) < 0.65)) {
            continue;
          }

          final recordArtist =
              _normalize(record['artistName']?.toString() ?? '');
          final wantedArtist = _normalize(cleanArtist);
          var score = recordTitle == wantedTitle ? 4 : 2;
          if (wantedArtist.isNotEmpty && recordArtist == wantedArtist) {
            score += 3;
          }
          if (duration != null && duration.inSeconds > 0) {
            final recordDuration = (record['duration'] as num?)?.toDouble();
            if (recordDuration != null) {
              final difference =
                  (recordDuration - duration.inMilliseconds / 1000).abs();
              if (difference <= 2) {
                score += 3;
              } else if (difference > 12) {
                // Search is often used when embedded file/video durations
                // differ from the LRCLIB recording. Penalize that candidate
                // without discarding an otherwise strong title/artist match.
                score -= difference > 90 ? 2 : 1;
              }
            }
          }

          final lyrics = _lyricsFromRecord(record);
          if (lyrics?.hasSyncedLyrics ?? false) {
            if (score > bestSyncedScore) {
              bestSyncedMatch = lyrics;
              bestSyncedScore = score;
            }
          } else if ((lyrics?.hasPlainLyrics ?? false) &&
              score > bestPlainScore) {
            bestPlainMatch = lyrics;
            bestPlainScore = score;
          }
          }
        }
      }
      return bestSyncedMatch ?? bestPlainMatch ?? exactPlainFallback;
    } catch (_) {
      return exactPlainFallback;
    }
  }

  LyricsData? _lyricsFromRecord(dynamic record) {
    if (record is! Map<String, dynamic>) return null;
    final plainLyrics = record['plainLyrics']?.toString();
    final syncedLyrics = record['syncedLyrics']?.toString();
    final lyrics = LyricsData(
      plainLyrics: plainLyrics,
      syncedLyrics: syncedLyrics,
      lines: _parseLrc(syncedLyrics),
    );
    return lyrics.hasLyrics ? lyrics : null;
  }

  String _cleanTitle(String value) {
    return value
        .replaceAll(
          RegExp(r'\.(?:mp3|m4a|aac|flac|wav|ogg|opus|wma)$', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._]\s*'), '')
        .replaceAll(RegExp(r'\s*\[(?:official|lyrics?|audio|video)[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\((?:official|lyrics?|audio|video)[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-|]\s*(?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?)(?:\s*video)?$', caseSensitive: false), '')
        .trim();
  }

  String _cleanArtist(String value) {
    return value.replaceFirst(RegExp(r'\s+-\s+Topic$', caseSensitive: false), '').trim();
  }

  bool _isGenericArtist(String value) {
    return const {
      'youtube',
      'unknown',
      'unknown artist',
      'artista desconocido',
      'unknown album',
      'álbum desconocido',
    }
        .contains(value.toLowerCase().trim());
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  double _titleSimilarity(String candidate, String requested) {
    final candidateWords = candidate.split(' ').where((word) => word.isNotEmpty).toSet();
    final requestedWords = requested.split(' ').where((word) => word.isNotEmpty).toSet();
    if (candidateWords.isEmpty || requestedWords.isEmpty) return 0;
    final overlap = candidateWords.intersection(requestedWords).length;
    return overlap / requestedWords.length;
  }

  List<LyricLine> _parseLrc(String? lrc) {
    if (lrc == null || lrc.trim().isEmpty) return const [];
    final result = <LyricLine>[];
    final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

    for (final rawLine in lrc.split(RegExp(r'\r?\n'))) {
      final timestamps = timestampPattern.allMatches(rawLine).toList();
      if (timestamps.isEmpty) continue;
      final text = rawLine.substring(timestamps.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in timestamps) {
        final minutes = int.tryParse(match.group(1) ?? '');
        final seconds = int.tryParse(match.group(2) ?? '');
        if (minutes == null || seconds == null) continue;
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final milliseconds = fraction.isEmpty
            ? 0
            : int.tryParse(fraction.substring(0, 3)) ?? 0;
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

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
