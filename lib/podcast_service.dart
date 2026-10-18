import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'music_player.dart';

class PodcastShow {
  const PodcastShow({
    required this.id,
    required this.title,
    required this.author,
    required this.artworkUrl,
    required this.feedUrl,
    required this.genre,
    required this.description,
    required this.storeUrl,
  });

  final String id;
  final String title;
  final String author;
  final String artworkUrl;
  final String feedUrl;
  final String genre;
  final String description;
  final String storeUrl;

  factory PodcastShow.fromApple(Map<String, dynamic> json) {
    final genres = json['genres'] as List? ?? const [];
    return PodcastShow(
      id: (json['collectionId'] ?? '').toString(),
      title: (json['collectionName'] ?? '').toString(),
      author: (json['artistName'] ?? '').toString(),
      artworkUrl: (json['artworkUrl600'] ?? json['artworkUrl100'] ?? '')
          .toString()
          .replaceAll('100x100', '600x600'),
      feedUrl: (json['feedUrl'] ?? '').toString(),
      genre: genres.isNotEmpty
          ? genres.first.toString()
          : (json['primaryGenreName'] ?? 'Podcast').toString(),
      description: (json['description'] ?? '').toString(),
      storeUrl: (json['collectionViewUrl'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'artworkUrl': artworkUrl,
    'feedUrl': feedUrl,
    'genre': genre,
    'description': description,
    'storeUrl': storeUrl,
  };

  factory PodcastShow.fromCache(Map<String, dynamic> json) => PodcastShow(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    author: json['author']?.toString() ?? '',
    artworkUrl: json['artworkUrl']?.toString() ?? '',
    feedUrl: json['feedUrl']?.toString() ?? '',
    genre: json['genre']?.toString() ?? 'Podcast',
    description: json['description']?.toString() ?? '',
    storeUrl: json['storeUrl']?.toString() ?? '',
  );
}

/// A public RSS source. The feed supplies its own episode audio URLs.
class PodcastFeed {
  const PodcastFeed({
    required this.id,
    required this.title,
    required this.category,
    required this.rssUrl,
  });

  final String id;
  final String title;
  final String category;
  final String rssUrl;
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.feedId,
    required this.showTitle,
    required this.category,
    required this.title,
    required this.description,
    required this.audioUrl,
    required this.artworkUrl,
    required this.duration,
    required this.publishedAt,
  });

  final String id;
  final String feedId;
  final String showTitle;
  final String category;
  final String title;
  final String description;
  final String audioUrl;
  final String artworkUrl;
  final Duration duration;
  final DateTime publishedAt;

  Song toSong() => Song(
    id: _stableSongId(id),
    title: title,
    displayName: title,
    artist: showTitle,
    album: showTitle,
    albumId: null,
    duration: duration.inMilliseconds,
    mimeType: 'podcast',
    size: 0,
    uri: audioUrl,
    artworkUri: artworkUrl,
    isMusic: false,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'feedId': feedId,
    'showTitle': showTitle,
    'category': category,
    'title': title,
    'description': description,
    'audioUrl': audioUrl,
    'artworkUrl': artworkUrl,
    'duration': duration.inMilliseconds,
    'publishedAt': publishedAt.toIso8601String(),
  };

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) => PodcastEpisode(
    id: json['id']?.toString() ?? '',
    feedId: json['feedId']?.toString() ?? '',
    showTitle: json['showTitle']?.toString() ?? 'Podcast',
    category: json['category']?.toString() ?? 'Podcast',
    title: json['title']?.toString() ?? 'Episodio',
    description: json['description']?.toString() ?? '',
    audioUrl: json['audioUrl']?.toString() ?? '',
    artworkUrl: json['artworkUrl']?.toString() ?? '',
    duration: Duration(milliseconds: (json['duration'] as num?)?.toInt() ?? 0),
    publishedAt:
        DateTime.tryParse(json['publishedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  static int _stableSongId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x3fffffff;
    }
    return 0x40000000 | hash;
  }
}

/// Reads public podcast RSS feeds, caches their episodes and tracks recently
/// played episode IDs so Home can keep recommendations fresh.
class PodcastService {
  PodcastService._();

  static final PodcastService instance = PodcastService._();

  static const feeds = <PodcastFeed>[
    PodcastFeed(
      id: 'diana-uribe',
      title: 'DianaUribe.fm',
      category: 'Historia y cultura',
      rssUrl: 'https://dianauribefm.libsyn.com/rss',
    ),
    PodcastFeed(
      id: 'huevos-revueltos',
      title: 'Huevos Revueltos con Política',
      category: 'Actualidad',
      rssUrl: 'https://www.spreaker.com/show/5392742/episodes/feed',
    ),
    PodcastFeed(
      id: 'memoria-caracol',
      title: 'Memoria',
      category: 'Historias de Colombia',
      rssUrl: 'https://www.omnycontent.com/d/playlist/40e16a8a-8434-4eb9-afd0-af3b00dad1ff/f09881d4-089a-4643-949a-af4d00f8c3ef/a32900d6-a69c-4ed1-98a7-af4d00f8c422/podcast.rss',
    ),
  ];

  static const _episodesCacheKey = 'soundneed_podcast_feed_cache_v1';
  static const _playedIdsKey = 'soundneed_podcast_recent_ids_v1';
  static const _listenedShowsKey = 'soundneed_podcast_listened_shows_v1';
  static const _listenedNamesKey = 'soundneed_podcast_listened_names_v1';
  static const _listenedGenresKey = 'soundneed_podcast_listened_genres_v1';
  static const _searchCachePrefix = 'soundneed_podcast_search_v1_';
  static const _searchCacheDuration = Duration(minutes: 30);
  static const _cacheDuration = Duration(minutes: 45);
  static const _recentLimit = 40;
  static const _xmlItunesNamespace =
      'http://www.itunes.com/dtds/podcast-1.0.dtd';

  final http.Client _client = http.Client();
  List<PodcastEpisode> _cachedEpisodes = const [];
  DateTime? _cachedAt;
  Future<List<PodcastEpisode>>? _pending;
  Future<void>? _initializing;
  SharedPreferences? _preferences;

  Future<void> _ensureInitialized() async {
    if (_preferences != null) return;
    final pending = _initializing;
    if (pending != null) return pending;

    final future = _loadCache();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _loadCache() async {
    _preferences = await SharedPreferences.getInstance();
    final raw = _preferences!.getString(_episodesCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _cachedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
      final values = decoded['episodes'];
      if (values is List) {
        _cachedEpisodes = values
            .whereType<Map>()
            .map(
              (item) =>
                  PodcastEpisode.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((episode) => _validAudioUrl(episode.audioUrl))
            .toList(growable: false);
      }
    } catch (_) {
      _cachedEpisodes = const [];
      _cachedAt = null;
    }
  }

  Future<List<PodcastEpisode>> loadLatest({bool forceRefresh = false}) async {
    await _ensureInitialized();
    final cacheIsFresh =
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration;
    if (!forceRefresh && _cachedEpisodes.isNotEmpty && cacheIsFresh) {
      return _recommendedOrder(_cachedEpisodes);
    }
    if (_pending != null) return _pending!;

    final request = _fetchAllFeeds();
    _pending = request;
    try {
      return await request;
    } finally {
      if (identical(_pending, request)) _pending = null;
    }
  }

  Future<List<PodcastShow>> searchPodcasts(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final preferences = await SharedPreferences.getInstance();
    final cacheKey =
        _searchCachePrefix +
        base64Url.encode(utf8.encode(normalized.toLowerCase()));
    final cached = preferences.getString(cacheKey);
    DateTime? cachedAt;
    List<PodcastShow> cachedShows = const [];
    if (cached != null) {
      try {
        final saved = jsonDecode(cached) as Map<String, dynamic>;
        cachedAt = DateTime.tryParse(saved['savedAt']?.toString() ?? '');
        cachedShows = (saved['shows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => PodcastShow.fromCache(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false);
        if (cachedAt != null &&
            DateTime.now().difference(cachedAt) < _searchCacheDuration) {
          return cachedShows;
        }
      } catch (_) {
        cachedShows = const [];
      }
    }
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': normalized,
        'media': 'podcast',
        'entity': 'podcast',
        'country': 'CO',
        'limit': '25',
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return cachedShows;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List? ?? const [];
      final seen = <String>{};
      final shows = results
          .whereType<Map>()
          .map((item) => PodcastShow.fromApple(Map<String, dynamic>.from(item)))
          .where(
            (show) =>
                show.id.isNotEmpty &&
                show.title.isNotEmpty &&
                _validAudioUrl(show.feedUrl) &&
                seen.add(show.id),
          )
          .toList(growable: false);
      await preferences.setString(
        cacheKey,
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'shows': shows.map((show) => show.toJson()).toList(),
        }),
      );
      return shows;
    } catch (_) {
      return cachedShows;
    }
  }

  Future<List<PodcastEpisode>> loadEpisodesForShow(PodcastShow show) async {
    if (!_validAudioUrl(show.feedUrl)) return const [];
    return _fetchFeed(
      PodcastFeed(
        id: show.id,
        title: show.title,
        category: show.genre,
        rssUrl: show.feedUrl,
      ),
    );
  }

  Future<List<PodcastShow>> recommendedPodcasts({int limit = 10}) async {
    await _ensureInitialized();
    final listened = _preferences!.getStringList(_listenedShowsKey) ?? const [];
    final listenedNames =
        _preferences!.getStringList(_listenedNamesKey) ?? const [];
    final genres = _preferences!.getStringList(_listenedGenresKey) ?? const [];
    final query = genres.isEmpty
        ? 'podcast Colombia español'
        : 'podcast ${genres.take(3).join(' ')} español';
    var results = await searchPodcasts(query);
    results = results
        .where(
          (show) =>
              !listened.contains(show.id) &&
              !listenedNames.contains(show.title.trim().toLowerCase()),
        )
        .toList();
    if (results.isEmpty && genres.isNotEmpty) {
      results = await searchPodcasts('podcast Colombia español');
      results = results
          .where(
            (show) =>
                !listened.contains(show.id) &&
                !listenedNames.contains(show.title.trim().toLowerCase()),
          )
          .toList();
    }
    return results.take(limit).toList(growable: false);
  }

  Future<List<PodcastEpisode>> _fetchAllFeeds() async {
    final results = await Future.wait(feeds.map(_fetchFeed));
    final refreshed = results.expand((episodes) => episodes).toList();
    final refreshedFeedIds = refreshed.map((episode) => episode.feedId).toSet();
    final combined = [
      ...refreshed,
      ..._cachedEpisodes.where(
        (episode) => !refreshedFeedIds.contains(episode.feedId),
      ),
    ];
    final seen = <String>{};
    _cachedEpisodes = combined
        .where((episode) => seen.add(episode.id))
        .toList(growable: false);
    _cachedAt = DateTime.now();
    await _preferences?.setString(
      _episodesCacheKey,
      jsonEncode({
        'savedAt': _cachedAt!.toIso8601String(),
        'episodes': _cachedEpisodes.map((episode) => episode.toJson()).toList(),
      }),
    );
    return _recommendedOrder(_cachedEpisodes);
  }

  Future<List<PodcastEpisode>> _fetchFeed(PodcastFeed feed) async {
    try {
      final response = await _client
          .get(
            Uri.parse(feed.rssUrl),
            headers: const {
              'Accept': 'application/rss+xml, application/xml, text/xml',
              'User-Agent': 'SoundNeed Podcast Player',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }

      final document = XmlDocument.parse(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      final channel = document.findAllElements('channel').firstOrNull;
      if (channel == null) return const [];

      final title = _childText(channel, 'title').trim();
      final artwork = _channelArtwork(channel);
      final episodes = <PodcastEpisode>[];

      for (final item in channel.findElements('item')) {
        final enclosure = item.findElements('enclosure').firstOrNull;
        final audioUrl = enclosure?.getAttribute('url')?.trim() ?? '';
        if (!_validAudioUrl(audioUrl)) continue;

        final episodeTitle = _childText(item, 'title').trim();
        if (episodeTitle.isEmpty) continue;
        final guid = _childText(item, 'guid').trim();
        final episodeArtwork = _episodeArtwork(item);
        final dateText = _childText(item, 'pubDate').trim();
        final description = _childText(item, 'description').trim();

        episodes.add(
          PodcastEpisode(
            id: '${feed.id}:${guid.isEmpty ? audioUrl : guid}',
            feedId: feed.id,
            showTitle: title.isEmpty ? feed.title : title,
            category: feed.category,
            title: episodeTitle,
            description: description,
            audioUrl: audioUrl,
            artworkUrl: episodeArtwork.isEmpty ? artwork : episodeArtwork,
            duration: _parseDuration(_itunesText(item, 'duration')),
            publishedAt: _parseDate(dateText),
          ),
        );
      }

      episodes.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return episodes;
    } catch (_) {
      // One unavailable feed should not hide episodes from the others.
      return const [];
    }
  }

  Future<void> markPlayed(PodcastEpisode episode, {PodcastShow? show}) async {
    await _ensureInitialized();
    final ids = _preferences!.getStringList(_playedIdsKey) ?? const [];
    final updated = <String>[
      episode.id,
      ...ids.where((id) => id != episode.id),
    ];
    await _preferences!.setStringList(
      _playedIdsKey,
      updated.take(_recentLimit).toList(growable: false),
    );

    final showId = show?.id ?? episode.feedId;
    final showIds = _preferences!.getStringList(_listenedShowsKey) ?? const [];
    await _preferences!.setStringList(
      _listenedShowsKey,
      [showId, ...showIds.where((id) => id != showId)].take(100).toList(),
    );
    final showName = (show?.title ?? episode.showTitle).trim().toLowerCase();
    final names = _preferences!.getStringList(_listenedNamesKey) ?? const [];
    if (showName.isNotEmpty) {
      await _preferences!.setStringList(
        _listenedNamesKey,
        [
          showName,
          ...names.where((name) => name != showName),
        ].take(100).toList(),
      );
    }
    final genre = show?.genre ?? episode.category;
    final genres = _preferences!.getStringList(_listenedGenresKey) ?? const [];
    if (genre.trim().isNotEmpty && genre != 'Podcast') {
      await _preferences!.setStringList(
        _listenedGenresKey,
        [genre, ...genres.where((value) => value != genre)].take(8).toList(),
      );
    }
  }

  List<PodcastEpisode> _recommendedOrder(List<PodcastEpisode> episodes) {
    final played = _preferences?.getStringList(_playedIdsKey)?.toSet() ?? {};
    final buckets = <String, List<PodcastEpisode>>{};
    for (final feed in feeds) {
      final feedEpisodes =
          episodes.where((episode) => episode.feedId == feed.id).toList()
            ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      final unseen = feedEpisodes.where(
        (episode) => !played.contains(episode.id),
      );
      final selected = unseen.isNotEmpty ? unseen.toList() : feedEpisodes;
      buckets[feed.id] = selected.take(8).toList();
    }

    final ordered = <PodcastEpisode>[];
    for (var index = 0; index < 8; index++) {
      final round = <PodcastEpisode>[];
      for (final feed in feeds) {
        final bucket = buckets[feed.id] ?? const <PodcastEpisode>[];
        if (index < bucket.length) round.add(bucket[index]);
      }
      round.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      ordered.addAll(round);
    }
    return ordered.take(12).toList(growable: false);
  }

  static String _childText(XmlElement element, String name) =>
      element.findElements(name).firstOrNull?.innerText ?? '';

  static String _itunesText(XmlElement element, String name) =>
      element
          .findElements(name, namespace: _xmlItunesNamespace)
          .firstOrNull
          ?.innerText ??
      '';

  static String _channelArtwork(XmlElement channel) {
    final namespacedImage = channel
        .findElements('image', namespace: _xmlItunesNamespace)
        .firstOrNull
        ?.getAttribute('href');
    if (namespacedImage != null && namespacedImage.isNotEmpty) {
      return namespacedImage;
    }
    final rssImage = channel.findElements('image').firstOrNull;
    final rssUrl = rssImage?.findElements('url').firstOrNull?.innerText.trim();
    if (rssUrl != null && rssUrl.isNotEmpty) return rssUrl;
    return '';
  }

  static String _episodeArtwork(XmlElement item) =>
      item
          .findElements('image', namespace: _xmlItunesNamespace)
          .firstOrNull
          ?.getAttribute('href')
          ?.trim() ??
      '';

  static bool _validAudioUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority;
  }

  static Duration _parseDuration(String value) {
    final parts = value.trim().split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((part) => part == null)) {
      return Duration.zero;
    }
    final numbers = parts.cast<int>();
    final seconds = switch (numbers.length) {
      3 => numbers[0] * 3600 + numbers[1] * 60 + numbers[2],
      2 => numbers[0] * 60 + numbers[1],
      1 => numbers[0],
      _ => 0,
    };
    return Duration(seconds: math.max(0, seconds));
  }

  static DateTime _parseDate(String value) {
    if (value.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ??
        _tryHttpDate(value) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _tryHttpDate(String value) {
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return null;
    }
  }
}
