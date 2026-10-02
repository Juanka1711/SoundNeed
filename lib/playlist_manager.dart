import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_player.dart';

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    required this.songs,
  });

  final String id;
  String name;
  final List<Song> songs;

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final songs = <Song>[];
    final savedSongs = json['songs'];
    if (savedSongs is List) {
      for (final item in savedSongs) {
        if (item is Map) {
          try {
            songs.add(Song.fromMap(Map<dynamic, dynamic>.from(item)));
          } catch (_) {
            // Ignore an invalid saved item and keep the rest of the playlist.
          }
        }
      }
    }

    return MusicPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Mi playlist',
      songs: songs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songs.map(_songToJson).toList(),
      };
}

/// Saves user playlists and liked songs locally on the device.
class PlaylistManager extends ChangeNotifier {
  PlaylistManager._();

  static final PlaylistManager instance = PlaylistManager._();
  static const _storageKey = 'soundneed_playlists_v1';

  List<MusicPlaylist> _playlists = [];
  List<Song> _likedSongs = [];
  Future<void>? _initializing;
  bool _initialized = false;

  List<MusicPlaylist> get playlists => List.unmodifiable(_playlists);
  List<Song> get likedSongs => List.unmodifiable(_likedSongs);

  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) return pending;

    final future = _load();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final savedPlaylists = decoded['playlists'];
          if (savedPlaylists is List) {
            _playlists = savedPlaylists
                .whereType<Map>()
                .map((item) => MusicPlaylist.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .where((playlist) => playlist.id.isNotEmpty)
                .toList();
          }

          final savedLikedSongs = decoded['likedSongs'];
          if (savedLikedSongs is List) {
            _likedSongs = _parseSongs(savedLikedSongs);
          }
        }
      } catch (error) {
        debugPrint('[PlaylistManager] No se pudieron cargar las playlists: $error');
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<MusicPlaylist> createPlaylist(String requestedName) async {
    await initialize();
    final name = _uniqueName(requestedName.trim());
    final playlist = MusicPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      songs: [],
    );
    _playlists.insert(0, playlist);
    await _save();
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String requestedName) async {
    await initialize();
    final playlist = findPlaylist(playlistId);
    if (playlist == null) return;

    playlist.name = _uniqueName(
      requestedName.trim(),
      excludingPlaylistId: playlistId,
    );
    await _save();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await initialize();
    _playlists.removeWhere((playlist) => playlist.id == playlistId);
    await _save();
    notifyListeners();
  }

  MusicPlaylist? findPlaylist(String playlistId) {
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) return playlist;
    }
    return null;
  }

  Future<bool> addSong(String playlistId, Song song) async {
    await initialize();
    final playlist = findPlaylist(playlistId);
    if (playlist == null) return false;
    if (playlist.songs.any((item) => songKey(item) == songKey(song))) {
      return false;
    }

    playlist.songs.add(song);
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> removeSong(String playlistId, Song song) async {
    await initialize();
    final playlist = findPlaylist(playlistId);
    if (playlist == null) return;
    playlist.songs.removeWhere((item) => songKey(item) == songKey(song));
    await _save();
    notifyListeners();
  }

  Future<void> setLikedSong(Song song, bool liked) async {
    await initialize();
    final key = songKey(song);
    _likedSongs.removeWhere((item) => songKey(item) == key);
    if (liked) _likedSongs.insert(0, song);
    await _save();
    notifyListeners();
  }

  String _uniqueName(String requestedName, {String? excludingPlaylistId}) {
    final base = requestedName.isEmpty ? 'Mi playlist' : requestedName;
    final existing = _playlists
        .where((item) => item.id != excludingPlaylistId)
        .map((item) => item.name.toLowerCase())
        .toSet();
    if (!existing.contains(base.toLowerCase())) return base;

    var suffix = 2;
    while (existing.contains('$base $suffix'.toLowerCase())) {
      suffix++;
    }
    return '$base $suffix';
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'version': 1,
      'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
      'likedSongs': _likedSongs.map(_songToJson).toList(),
    });
    await preferences.setString(_storageKey, encoded);
  }
}

String songKey(Song song) =>
    song.isOnline ? 'youtube:${song.onlineVideoId}' : 'local:${song.id}';

List<Song> _parseSongs(List<dynamic> values) {
  final songs = <Song>[];
  final seen = <String>{};
  for (final item in values) {
    if (item is! Map) continue;
    try {
      final song = Song.fromMap(Map<dynamic, dynamic>.from(item));
      if (songKey(song).endsWith(':')) continue;
      if (seen.add(songKey(song))) songs.add(song);
    } catch (_) {
      // Ignore a damaged song entry without losing the other saved items.
    }
  }
  return songs;
}

Map<String, dynamic> _songToJson(Song song) => {
      'id': song.id,
      'title': song.title,
      'displayName': song.displayName,
      'artist': song.artist,
      'album': song.album,
      'albumId': song.albumId,
      'duration': song.duration,
      'mimeType': song.mimeType,
      'size': song.size,
      'uri': song.uri,
      'artworkUri': song.artworkUri,
      'isMusic': song.isMusic,
    };
