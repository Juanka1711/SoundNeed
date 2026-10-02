import 'package:flutter/foundation.dart';

import 'services/youtube_audio_service.dart';

/// Shared source for the current music discoveries shown in Home and Artists.
/// Both screens use the same list; refreshing either screen replaces it.
class ArtistDiscoveryService {
  ArtistDiscoveryService._();

  static final ArtistDiscoveryService instance = ArtistDiscoveryService._();

  static const _query = 'música nueva y tendencias Colombia';
  static const _cacheDuration = Duration(minutes: 20);

  List<YouTubeSearchResult> _results = const [];
  DateTime? _loadedAt;
  Future<List<YouTubeSearchResult>>? _pending;

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
