import 'dart:convert';

import 'package:http/http.dart' as http;

class DiscoveredAlbumTrack {
  const DiscoveredAlbumTrack({
    required this.title,
    required this.artist,
    required this.durationSeconds,
  });

  final String title;
  final String artist;
  final int durationSeconds;
}

class DiscoveredAlbum {
  const DiscoveredAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.releaseDate,
    required this.tracks,
  });

  final int id;
  final String title;
  final String artist;
  final String coverUrl;
  final String releaseDate;
  final List<DiscoveredAlbumTrack> tracks;
}

/// Looks up a track on Deezer to resolve its album when local tags are absent.
class AlbumLookupService {
  AlbumLookupService._();

  static final AlbumLookupService instance = AlbumLookupService._();
  final http.Client _client = http.Client();

  Future<DiscoveredAlbum?> findAlbum({
    required String title,
    required String artist,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty) return null;

    final queries = <String>{
      '$cleanTitle $cleanArtist'.trim(),
      cleanTitle,
    };
    Map<String, dynamic>? bestTrack;
    var bestScore = 0.0;
    for (final query in queries) {
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/search/track', {'q': query}),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) continue;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) continue;
      for (final raw in decoded['data'] as List) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final candidateTitle = item['title']?.toString() ?? '';
        final candidateArtist = (item['artist'] is Map)
            ? (item['artist'] as Map)['name']?.toString() ?? ''
            : '';
        final titleScore = _matchScore(cleanTitle, candidateTitle);
        final artistScore = cleanArtist.isEmpty
            ? .5
            : _matchScore(cleanArtist, candidateArtist);
        final score = titleScore * .72 + artistScore * .28;
        final enoughMatch = titleScore >= .48 &&
            (cleanArtist.isEmpty || artistScore >= .28);
        if (enoughMatch && score > bestScore) {
          bestTrack = item;
          bestScore = score;
        }
      }
      if (bestScore >= .95) break;
    }

    final albumData = bestTrack?['album'];
    final albumId = albumData is Map
        ? (albumData['id'] as num?)?.toInt()
        : null;
    if (albumId == null || albumId <= 0) return null;

    final response = await _client
        .get(
          Uri.https('api.deezer.com', '/album/$albumId'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final album = Map<String, dynamic>.from(decoded);
    final albumArtist = album['artist'] is Map
        ? (album['artist'] as Map)['name']?.toString() ?? cleanArtist
        : cleanArtist;
    final tracks = await _loadTracks(albumId, albumArtist, album);
    return DiscoveredAlbum(
      id: albumId,
      title: album['title']?.toString().trim().isNotEmpty == true
          ? album['title'].toString().trim()
          : (albumData is Map ? albumData['title']?.toString() : null) ??
                'Álbum',
      artist: albumArtist,
      coverUrl: (album['cover_xl'] ??
              album['cover_big'] ??
              (albumData is Map ? albumData['cover_big'] : null) ??
              (albumData is Map ? albumData['cover'] : null))
          ?.toString() ??
          '',
      releaseDate: album['release_date']?.toString() ?? '',
      tracks: List.unmodifiable(tracks),
    );
  }

  Future<List<DiscoveredAlbumTrack>> _loadTracks(
    int albumId,
    String albumArtist,
    Map<String, dynamic> album,
  ) async {
    try {
      final response = await _client
          .get(
            Uri.https('api.deezer.com', '/album/$albumId/tracks'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return const [];
      return (decoded['data'] as List)
          .whereType<Map>()
          .map(
            (track) => DiscoveredAlbumTrack(
              title: track['title']?.toString() ?? 'Canción',
              artist: track['artist'] is Map
                  ? (track['artist'] as Map)['name']?.toString() ?? albumArtist
                  : albumArtist,
              durationSeconds: (track['duration'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } catch (_) {
      final embedded = album['tracks'];
      if (embedded is! Map || embedded['data'] is! List) return const [];
      return (embedded['data'] as List)
          .whereType<Map>()
          .map(
            (track) => DiscoveredAlbumTrack(
              title: track['title']?.toString() ?? 'Canción',
              artist: albumArtist,
              durationSeconds: (track['duration'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    }
  }

  double _matchScore(String wanted, String candidate) {
    final wantedTokens = _tokens(wanted);
    final candidateTokens = _tokens(candidate);
    if (wantedTokens.isEmpty || candidateTokens.isEmpty) return 0;
    final overlap = wantedTokens.intersection(candidateTokens).length;
    return overlap / wantedTokens.length;
  }

  Set<String> _tokens(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ');
    const ignored = {
      'official', 'video', 'audio', 'lyrics', 'lyric', 'visualizer',
      'music', 'vevo', 'hd', '4k', 'remaster', 'remastered', 'feat',
      'ft', 'topic', 'version', 'letra', 'videoclip',
    };
    return normalized
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 1 && !ignored.contains(word))
        .toSet();
  }
}
