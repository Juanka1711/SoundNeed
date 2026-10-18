import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/youtube_audio_service.dart';

class MusicChartTrack {
  const MusicChartTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.storeUrl,
    required this.rank,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final String storeUrl;
  final int rank;

  factory MusicChartTrack.fromJson(Map<String, dynamic> json, int rank) {
    final attributes = json['attributes'] is Map
        ? Map<String, dynamic>.from(json['attributes'] as Map)
        : json;
    return MusicChartTrack(
      id: (json['id'] ?? attributes['trackId'] ?? '').toString(),
      title: (attributes['name'] ?? attributes['trackName'] ?? '').toString(),
      artist: (attributes['artistName'] ?? '').toString(),
      artworkUrl:
          (attributes['artworkUrl100'] ?? attributes['artworkUrl60'] ?? '')
              .toString()
              .replaceAll('100x100', '600x600'),
      storeUrl: (attributes['url'] ?? '').toString(),
      rank: rank,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'storeUrl': storeUrl,
    'rank': rank,
  };

  factory MusicChartTrack.fromCache(Map<String, dynamic> json) =>
      MusicChartTrack(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        artworkUrl: json['artworkUrl']?.toString() ?? '',
        storeUrl: json['storeUrl']?.toString() ?? '',
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );
}

class MusicChartArtist {
  const MusicChartArtist({
    required this.name,
    required this.artworkUrl,
    required this.rank,
    required this.songs,
  });

  final String name;
  final String artworkUrl;
  final int rank;
  final List<MusicChartTrack> songs;
}

/// Shared source for the current music discoveries shown in Home and Artists.
/// Both screens use the same list; refreshing either screen replaces it.
class ArtistDiscoveryService {
  ArtistDiscoveryService._();

  static final ArtistDiscoveryService instance = ArtistDiscoveryService._();

  static const _query = 'música nueva y tendencias Colombia';
  static const _cacheDuration = Duration(minutes: 20);
  static const _chartCacheKey = 'soundneed_colombia_music_chart_v1';
  static const _worldChartCacheKey = 'soundneed_world_music_chart_v1';
  static const _worldMonthlyCacheKey = 'soundneed_world_music_monthly_v1';
  // Recheck while the app is active so a provider update is not hidden behind
  // an old local chart cache for most of the day.
  static const _chartCacheDuration = Duration(minutes: 45);
  static const _monthlyWindow = Duration(days: 30);
  static const _worldMarkets = [
    'us',
    'gb',
    'mx',
    'br',
    'ca',
    'au',
    'es',
    'de',
    'fr',
    'jp',
    'kr',
    'in',
  ];

  List<YouTubeSearchResult> _results = const [];
  DateTime? _loadedAt;
  Future<List<YouTubeSearchResult>>? _pending;
  List<MusicChartTrack> _chart = const [];
  DateTime? _chartLoadedAt;
  Future<List<MusicChartTrack>>? _chartPending;
  List<MusicChartTrack> _worldChart = const [];
  DateTime? _worldChartLoadedAt;
  Future<List<MusicChartTrack>>? _worldChartPending;
  List<Map<String, dynamic>> _worldSnapshots = const [];
  bool _worldSnapshotsLoaded = false;
  final Map<String, YouTubeSearchResult> _resolvedChartResults = {};

  Future<List<MusicChartTrack>> loadCurrentChart({
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (_chart.isEmpty) {
      final cached = prefs.getString(_chartCacheKey);
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          _chartLoadedAt = DateTime.tryParse(
            decoded['savedAt']?.toString() ?? '',
          );
          _chart = (decoded['tracks'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    MusicChartTrack.fromCache(Map<String, dynamic>.from(item)),
              )
              .where((item) => item.title.isNotEmpty)
              .toList(growable: false);
        } catch (_) {
          _chart = const [];
          _chartLoadedAt = null;
        }
      }
    }

    final fresh =
        _chartLoadedAt != null &&
        DateTime.now().difference(_chartLoadedAt!) < _chartCacheDuration;
    if (!forceRefresh && fresh && _chart.isNotEmpty) return chart;
    if (_chartPending != null) return _chartPending!;

    final request = _fetchCurrentChart(prefs);
    _chartPending = request;
    try {
      return await request;
    } finally {
      if (identical(_chartPending, request)) _chartPending = null;
    }
  }

  List<MusicChartTrack> get chart => List.unmodifiable(_chart);

  List<MusicChartTrack> get worldChart => List.unmodifiable(_worldChart);

  /// Resuelve una cola con una búsqueda individual por cada tema del chart.
  /// Evita llenar la cola con versiones del mismo tema y portadas distintas.
  Future<List<YouTubeSearchResult>> resolvePlaybackQueue(
    List<MusicChartTrack> tracks, {
    required MusicChartTrack startWith,
    YouTubeSearchResult? firstResult,
    int limit = 6,
  }) async {
    if (tracks.isEmpty) return const [];

    final startIndex = tracks.indexWhere(
      (track) =>
          track.id == startWith.id &&
          track.title == startWith.title &&
          track.artist == startWith.artist,
    );
    final ordered = startIndex < 0
        ? <MusicChartTrack>[startWith, ...tracks]
        : <MusicChartTrack>[
            ...tracks.skip(startIndex),
            ...tracks.take(startIndex),
          ];

    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(
          RegExp(r'\b(topic|official|audio|video|lyrics?)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    double titleMatch(String resultTitle, String wantedTitle) {
      final result = normalize(resultTitle);
      final wanted = normalize(wantedTitle);
      if (result.isEmpty || wanted.isEmpty) return 0;
      if (result == wanted) return 1;
      if (result.contains(wanted) || wanted.contains(result)) return 0.92;
      final resultWords = result
          .split(' ')
          .where((word) => word.length > 1)
          .toSet();
      final wantedWords = wanted
          .split(' ')
          .where((word) => word.length > 1)
          .toSet();
      if (wantedWords.isEmpty) return 0;
      return resultWords.intersection(wantedWords).length / wantedWords.length;
    }

    double artistMatch(
      String resultTitle,
      String resultArtist,
      MusicChartTrack track,
    ) {
      final result = normalize('$resultTitle $resultArtist');
      final wanted = normalize(track.artist);
      if (result.isEmpty || wanted.isEmpty) return 0;
      if (result.contains(wanted) || wanted.contains(result)) return 0.15;
      final resultWords = result.split(' ').where((word) => word.length > 1).toSet();
      final wantedWords = wanted.split(' ').where((word) => word.length > 1).toSet();
      if (wantedWords.isEmpty) return 0;
      final overlap = resultWords.intersection(wantedWords).length;
      return overlap == 0 ? 0 : 0.08 * overlap / wantedWords.length;
    }

    final uniqueTracks = <MusicChartTrack>[];
    final trackKeys = <String>{};
    for (final track in ordered) {
      final key = '${normalize(track.title)}|${normalize(track.artist)}';
      if (track.title.trim().isEmpty || !trackKeys.add(key)) continue;
      uniqueTracks.add(track);
      if (uniqueTracks.length >= limit) break;
    }

    Future<(MusicChartTrack, YouTubeSearchResult?)> resolve(
      MusicChartTrack track,
    ) async {
      final key = '${normalize(track.title)}|${normalize(track.artist)}';
      if (key ==
              '${normalize(startWith.title)}|${normalize(startWith.artist)}' &&
          firstResult != null) {
        _resolvedChartResults[key] = firstResult;
        return (track, firstResult);
      }
      final cached = _resolvedChartResults[key];
      if (cached != null) return (track, cached);
      try {
        final results = await YouTubeAudioService.instance.search(
          '${track.title} ${track.artist} audio',
        );
        YouTubeSearchResult? best;
        var bestScore = 0.0;
        for (final result in results) {
          final titleScore = titleMatch(result.title, track.title);
          final score =
              titleScore + artistMatch(result.title, result.artist, track);
          if (score > bestScore) {
            best = result;
            bestScore = score;
          }
        }
        if (best != null && bestScore >= 0.55) {
          _resolvedChartResults[key] = best;
          return (track, best);
        }
      } catch (_) {
        // Una búsqueda fallida no cancela el resto de la cola.
      }
      return (track, null);
    }

    final resolved = await Future.wait(uniqueTracks.map(resolve));
    final seenVideoIds = <String>{};
    final seenSongs = <String>{};
    return List.unmodifiable([
      for (final item in resolved)
        if (item.$2 != null &&
            seenVideoIds.add(item.$2!.videoId) &&
            seenSongs.add(
              '${normalize(item.$2!.title)}|${normalize(item.$2!.artist)}',
            ))
          item.$2!,
    ]);
  }

  Future<List<MusicChartTrack>> loadWorldChart({
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _loadWorldSnapshots(prefs);
    if (_worldChart.isEmpty) {
      final cached = prefs.getString(_worldChartCacheKey);
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          _worldChartLoadedAt = DateTime.tryParse(
            decoded['savedAt']?.toString() ?? '',
          );
          _worldChart = (decoded['tracks'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    MusicChartTrack.fromCache(Map<String, dynamic>.from(item)),
              )
              .where((item) => item.title.isNotEmpty)
              .toList(growable: false);
        } catch (_) {
          _worldChart = const [];
          _worldChartLoadedAt = null;
        }
      }
    }

    final fresh =
        _worldChartLoadedAt != null &&
        DateTime.now().difference(_worldChartLoadedAt!) < _chartCacheDuration;
    if (_worldSnapshots.isEmpty && _worldChart.isNotEmpty) {
      await _recordWorldSnapshot(prefs);
    }
    if (!forceRefresh && fresh && _worldChart.isNotEmpty) return worldChart;
    if (_worldChartPending != null) return _worldChartPending!;

    final request = _fetchWorldChart(prefs);
    _worldChartPending = request;
    try {
      return await request;
    } finally {
      if (identical(_worldChartPending, request)) _worldChartPending = null;
    }
  }

  List<MusicChartArtist> get worldArtists {
    if (_worldSnapshots.isNotEmpty) return _rankMonthlyArtists();
    final groups = <String, List<MusicChartTrack>>{};
    for (final song in _worldChart) {
      final key = song.artist.trim().toLowerCase();
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(song);
    }
    final scored = groups.entries.map((entry) {
      final songs = [...entry.value]..sort((a, b) => a.rank.compareTo(b.rank));
      final score = songs.fold<int>(0, (sum, song) => sum + (601 - song.rank));
      return (score: score, songs: songs);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));
    return List.unmodifiable([
      for (var index = 0; index < scored.length; index++)
        MusicChartArtist(
          name: scored[index].songs.first.artist,
          artworkUrl: scored[index].songs.first.artworkUrl,
          rank: index + 1,
          songs: List.unmodifiable(scored[index].songs.take(5)),
        ),
    ]);
  }

  int get monthlySnapshotDays => _worldSnapshots.length;

  Future<void> _loadWorldSnapshots(SharedPreferences prefs) async {
    if (_worldSnapshotsLoaded) return;
    _worldSnapshotsLoaded = true;
    final encoded = prefs.getString(_worldMonthlyCacheKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded) as List? ?? const [];
      final cutoff = DateTime.now().subtract(_monthlyWindow);
      _worldSnapshots = decoded
          .whereType<Map>()
          .map((snapshot) => Map<String, dynamic>.from(snapshot))
          .where((snapshot) {
            final date = DateTime.tryParse(snapshot['date']?.toString() ?? '');
            return date != null && !date.isBefore(cutoff);
          })
          .toList(growable: false);
    } catch (_) {
      _worldSnapshots = const [];
    }
  }

  List<MusicChartArtist> _rankMonthlyArtists() {
    final artistScores = <String, int>{};
    final artistNames = <String, String>{};
    final artistSongs = <String, Map<String, _MonthlyTrackScore>>{};
    for (final snapshot in _worldSnapshots) {
      final entries = snapshot['tracks'] as List? ?? const [];
      for (final value in entries.whereType<Map>()) {
        final entry = Map<String, dynamic>.from(value);
        final artist = entry['artist']?.toString().trim() ?? '';
        final title = entry['title']?.toString().trim() ?? '';
        final rank = (entry['rank'] as num?)?.toInt() ?? 0;
        if (artist.isEmpty || title.isEmpty || rank < 1) continue;
        final artistKey = artist.toLowerCase();
        final songKey = title.toLowerCase();
        final points = (101 - rank.clamp(1, 100)).toInt();
        artistScores.update(
          artistKey,
          (score) => score + points,
          ifAbsent: () => points,
        );
        artistNames.putIfAbsent(artistKey, () => artist);
        final songs = artistSongs.putIfAbsent(artistKey, () => {});
        final old = songs[songKey];
        if (old == null) {
          songs[songKey] = _MonthlyTrackScore(
            title: title,
            artist: artist,
            points: points,
            artworkUrl: entry['artworkUrl']?.toString() ?? '',
          );
        } else {
          old.points += points;
        }
      }
    }
    final keys = artistScores.keys.toList()
      ..sort((a, b) => artistScores[b]!.compareTo(artistScores[a]!));
    final artists = <MusicChartArtist>[];
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      final songs = artistSongs[key]!.values.toList()
        ..sort((a, b) => b.points.compareTo(a.points));
      final tracks = [
        for (var songIndex = 0; songIndex < songs.length; songIndex++)
          MusicChartTrack(
            id: '',
            title: songs[songIndex].title,
            artist: songs[songIndex].artist,
            artworkUrl: songs[songIndex].artworkUrl,
            storeUrl: '',
            rank: songIndex + 1,
          ),
      ];
      artists.add(
        MusicChartArtist(
          name: artistNames[key]!,
          artworkUrl: tracks.isEmpty ? '' : tracks.first.artworkUrl,
          rank: index + 1,
          songs: List.unmodifiable(tracks.take(5)),
        ),
      );
    }
    return List.unmodifiable(artists);
  }

  Future<List<MusicChartTrack>> _fetchWorldChart(
    SharedPreferences prefs,
  ) async {
    try {
      final responses = await Future.wait(
        _worldMarkets.map((market) async {
          try {
            final uri = Uri.https(
              'rss.applemarketingtools.com',
              '/api/v2/$market/music/most-played/50/songs.json',
            );
            final response = await http
                .get(
                  uri,
                  headers: const {
                    'Cache-Control': 'no-cache',
                    'Pragma': 'no-cache',
                  },
                )
                .timeout(const Duration(seconds: 15));
            if (response.statusCode != 200) return const <MusicChartTrack>[];
            final decoded = jsonDecode(response.body) as Map<String, dynamic>;
            final feed = decoded['feed'] as Map<String, dynamic>?;
            final results = feed?['results'] as List? ?? const [];
            return [
              for (var index = 0; index < results.length; index++)
                if (results[index] is Map)
                  MusicChartTrack.fromJson(
                    Map<String, dynamic>.from(results[index] as Map),
                    index + 1,
                  ),
            ];
          } catch (_) {
            return const <MusicChartTrack>[];
          }
        }),
      );

      final scores = <String, int>{};
      final tracks = <String, MusicChartTrack>{};
      for (final response in responses) {
        for (final track in response) {
          if (track.title.isEmpty || track.artist.isEmpty) continue;
          final key =
              '${track.title.trim().toLowerCase()}|'
              '${track.artist.trim().toLowerCase()}';
          scores.update(
            key,
            (score) => score + (51 - track.rank),
            ifAbsent: () => 51 - track.rank,
          );
          tracks.putIfAbsent(key, () => track);
        }
      }
      final rankedKeys = scores.keys.toList()
        ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      if (rankedKeys.isNotEmpty) {
        _worldChart = [
          for (var index = 0; index < rankedKeys.length; index++)
            MusicChartTrack(
              id: tracks[rankedKeys[index]]!.id,
              title: tracks[rankedKeys[index]]!.title,
              artist: tracks[rankedKeys[index]]!.artist,
              artworkUrl: tracks[rankedKeys[index]]!.artworkUrl,
              storeUrl: tracks[rankedKeys[index]]!.storeUrl,
              rank: index + 1,
            ),
        ];
        _worldChartLoadedAt = DateTime.now();
        await _recordWorldSnapshot(prefs);
        await prefs.setString(
          _worldChartCacheKey,
          jsonEncode({
            'savedAt': _worldChartLoadedAt!.toIso8601String(),
            'tracks': _worldChart.map((track) => track.toJson()).toList(),
          }),
        );
      }
    } catch (error) {
      debugPrint(
        '[ArtistDiscovery] No se pudo actualizar el chart mundial: $error',
      );
    }
    return worldChart;
  }

  Future<void> _recordWorldSnapshot(SharedPreferences prefs) async {
    final today = DateTime.now();
    final dayKey =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final cutoff = today.subtract(_monthlyWindow);
    final snapshots = _worldSnapshots
        .where((snapshot) {
          final date = DateTime.tryParse(snapshot['date']?.toString() ?? '');
          return date != null && !date.isBefore(cutoff);
        })
        .where((snapshot) => snapshot['date'] != dayKey)
        .toList();
    snapshots.add({
      'date': dayKey,
      'tracks': [
        for (final track in _worldChart.take(100))
          {
            'title': track.title,
            'artist': track.artist,
            'rank': track.rank,
            'artworkUrl': track.artworkUrl,
          },
      ],
    });
    snapshots.sort(
      (a, b) =>
          (a['date']?.toString() ?? '').compareTo(b['date']?.toString() ?? ''),
    );
    _worldSnapshots = snapshots;
    _worldSnapshotsLoaded = true;
    await prefs.setString(_worldMonthlyCacheKey, jsonEncode(snapshots));
  }

  Future<List<MusicChartTrack>> _fetchCurrentChart(
    SharedPreferences prefs,
  ) async {
    try {
      final uri = Uri.https(
        'rss.applemarketingtools.com',
        '/api/v2/co/music/most-played/50/songs.json',
      );
      final response = await http
          .get(
            uri,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return chart;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final feed = decoded['feed'] as Map<String, dynamic>?;
      final results = feed?['results'] as List? ?? const [];
      final tracks = <MusicChartTrack>[];
      for (var index = 0; index < results.length; index++) {
        final item = results[index];
        if (item is! Map) continue;
        final track = MusicChartTrack.fromJson(
          Map<String, dynamic>.from(item),
          index + 1,
        );
        if (track.title.isNotEmpty && track.artist.isNotEmpty) {
          tracks.add(track);
        }
      }
      if (tracks.isNotEmpty) {
        _chart = tracks;
        _chartLoadedAt = DateTime.now();
        await prefs.setString(
          _chartCacheKey,
          jsonEncode({
            'savedAt': _chartLoadedAt!.toIso8601String(),
            'tracks': _chart.map((track) => track.toJson()).toList(),
          }),
        );
      }
    } catch (error) {
      debugPrint('[ArtistDiscovery] No se pudo actualizar el chart: $error');
    }
    return chart;
  }

  List<YouTubeSearchResult> get results => List.unmodifiable(_results);

  Future<List<YouTubeSearchResult>> load({bool forceRefresh = false}) async {
    final isFresh =
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _cacheDuration;
    if (!forceRefresh && isFresh && _results.isNotEmpty) return results;
    if (_pending != null) return _pending!;

    final request = _fetch();
    _pending = request;
    try {
      return await request;
    } finally {
      if (identical(_pending, request)) _pending = null;
    }
  }

  Future<List<YouTubeSearchResult>> _fetch() async {
    final found = await YouTubeAudioService.instance.search(_query);
    final seen = <String>{};
    _results = found
        .where((item) => item.videoId.isNotEmpty && seen.add(item.videoId))
        .take(10)
        .toList(growable: false);
    _loadedAt = DateTime.now();
    debugPrint('[ArtistDiscovery] Loaded ${_results.length} suggestions');
    return results;
  }
}

class _MonthlyTrackScore {
  _MonthlyTrackScore({
    required this.title,
    required this.artist,
    required this.points,
    required this.artworkUrl,
  });

  final String title;
  final String artist;
  int points;
  final String artworkUrl;
}
