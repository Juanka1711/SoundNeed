import 'dart:convert';

import 'package:http/http.dart' as http;

class ArtistCatalogEntry {
  const ArtistCatalogEntry({
    required this.name,
    required this.pictureUrl,
    required this.fanCount,
  });

  final String name;
  final String pictureUrl;
  final int? fanCount;
}

/// Retrieves current artist portraits and public fan counts for artist pages.
/// Search results are accepted only when the artist name matches exactly.
class ArtistCatalogService {
  ArtistCatalogService._();

  static final ArtistCatalogService instance = ArtistCatalogService._();

  static const _cacheDuration = Duration(hours: 6);
  final Map<String, _CachedArtist> _cache = {};
  final Map<String, Future<ArtistCatalogEntry?>> _pending = {};
  final http.Client _client = http.Client();

  Future<ArtistCatalogEntry?> lookup(
    String artistName, {
    bool forceRefresh = false,
  }) {
    final query = artistName.trim();
    if (query.isEmpty) return Future.value(null);

    final key = _normalize(query);
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheDuration) {
      return Future.value(cached.entry);
    }

    return _pending.putIfAbsent(key, () => _fetch(query, key));
  }

  Future<ArtistCatalogEntry?> _fetch(String artistName, String key) async {
    try {
      final uri = Uri.https('api.deezer.com', '/search/artist', {
        'q': artistName,
      });
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _cacheNull(key);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return _cacheNull(key);

      for (final item in decoded['data'] as List) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (_normalize(name) != key) continue;
        final picture =
            (item['picture_xl'] ??
                    item['picture_big'] ??
                    item['picture_medium'])
                ?.toString()
                .trim();
        if (picture == null || !picture.startsWith('https://')) {
          return _cacheNull(key);
        }

        final rawFans = item['nb_fan'];
        final entry = ArtistCatalogEntry(
          name: name,
          pictureUrl: picture,
          fanCount: rawFans is num ? rawFans.toInt() : int.tryParse('$rawFans'),
        );
        _cache[key] = _CachedArtist(entry, DateTime.now());
        return entry;
      }
      return _cacheNull(key);
    } catch (_) {
      return _cacheNull(key);
    } finally {
      _pending.remove(key);
    }
  }

  ArtistCatalogEntry? _cacheNull(String key) {
    _cache[key] = _CachedArtist(null, DateTime.now());
    return null;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _CachedArtist {
  const _CachedArtist(this.entry, this.savedAt);

  final ArtistCatalogEntry? entry;
  final DateTime savedAt;
}
