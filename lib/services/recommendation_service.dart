import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'youtube_audio_service.dart';

/// ============================================================
/// SOUNDNEED - RECOMMENDATION SERVICE
/// ============================================================
///
/// Sistema local de aprendizaje musical.
///
/// NO utiliza:
/// - SQLite
/// - servidor
/// - API externa
/// - inteligencia artificial
/// - categorías predefinidas
/// - artistas predefinidos
///
/// Aprende exclusivamente del comportamiento del usuario.
///
/// Guarda localmente:
/// - canciones reproducidas
/// - artistas
/// - reproducciones
/// - skips
/// - tiempo escuchado
/// - canciones completadas
/// - repeticiones
/// - favoritos
/// - última reproducción
/// - preferencias aprendidas
/// - sesiones generadas
///
/// El servicio está diseñado para trabajar tanto con:
/// - canciones locales
/// - resultados de YouTube
///
/// ============================================================

class RecommendationService {
  RecommendationService._();

  static final RecommendationService instance =
      RecommendationService._();

  static const String _storageKey = 'soundneed_recommendation_data_v1';

  SharedPreferences? _preferences;

  RecommendationDatabase _database = RecommendationDatabase.empty();

  final Random _random = Random();

  /// Canción actualmente reproduciéndose.
  String? _currentSongId;

  /// Momento en que comenzó la reproducción.
  DateTime? _currentStartedAt;

  /// Información de la reproducción actual.
  ListeningEvent? _currentEvent;

  bool _initialized = false;

  /// Canciones descubiertas por búsqueda automática.
  final Map<String, DiscoveredSong> _discoveredSongs = {};

  /// ==========================================================
  /// INICIALIZACIÓN
  /// ==========================================================

  Future<void> initialize() async {
    if (_initialized) return;

    _preferences = await SharedPreferences.getInstance();

    final raw = _preferences!.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map<String, dynamic>) {
          _database = RecommendationDatabase.fromJson(decoded);
        } else if (decoded is Map) {
          _database = RecommendationDatabase.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }

        // Limpiar canciones con videoIds inválidos
        _cleanupInvalidSongs();
      } catch (e) {
        debugPrint(
          '[RecommendationService] '
          'No se pudo cargar el historial: $e',
        );

        _database = RecommendationDatabase.empty();
      }
    }

    _initialized = true;

    debugPrint(
      '[RecommendationService] Inicializado. '
      'Canciones conocidas: ${_database.songs.length}',
    );
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// ==========================================================
  /// GUARDADO
  /// ==========================================================

  Future<void> _save() async {
    await _ensureInitialized();

    final encoded = jsonEncode(_database.toJson());

    await _preferences!.setString(
      _storageKey,
      encoded,
    );
  }

  /// ==========================================================
  /// COMENZAR REPRODUCCIÓN
  /// ==========================================================
  ///
  /// Llamar cada vez que una canción empieza.
  ///
  /// Ejemplo:
  ///
  /// await RecommendationService.instance.startListening(
  ///   id: song.id,
  ///   title: song.title,
  ///   artist: song.artist,
  /// );
  ///
  Future<void> startListening({
    required String id,
    required String title,
    required String artist,
    String? thumbnail,
    String? source,
    int durationSeconds = 0,
  }) async {
    await _ensureInitialized();

    final normalizedId = id.trim();

    if (normalizedId.isEmpty) return;

    // Validar videoId para canciones de YouTube
    if (source == 'youtube' && !_isValidYouTubeVideoId(normalizedId)) {
      debugPrint(
        '[RecommendationService] Ignorando canción con videoId inválido: $normalizedId',
      );
      return;
    }

    /// Si había otra canción reproduciéndose,
    /// cerramos correctamente su evento.
    if (_currentSongId != null &&
        _currentSongId != normalizedId) {
      await stopListening();
    }

    final now = DateTime.now();

    final song = _database.songs[normalizedId];

    if (song == null) {
      _database.songs[normalizedId] = LearnedSong(
        id: normalizedId,
        title: title.trim(),
        artist: artist.trim(),
        thumbnail: thumbnail ?? '',
        source: source ?? 'unknown',
        durationSeconds: durationSeconds,
        playCount: 1,
        completedCount: 0,
        skipCount: 0,
        favorite: false,
        totalListenedSeconds: 0,
        firstPlayedAt: now,
        lastPlayedAt: now,
      );
    } else {
      song.title = title.trim().isNotEmpty
          ? title.trim()
          : song.title;

      song.artist = artist.trim().isNotEmpty
          ? artist.trim()
          : song.artist;

      if (thumbnail != null && thumbnail.isNotEmpty) {
        song.thumbnail = thumbnail;
      }

      if (source != null && source.isNotEmpty) {
        song.source = source;
      }

      if (durationSeconds > 0) {
        song.durationSeconds = durationSeconds;
      }

      song.playCount++;
      song.lastPlayedAt = now;
    }

    _currentSongId = normalizedId;
    _currentStartedAt = now;

    _currentEvent = ListeningEvent(
      id: _createEventId(),
      songId: normalizedId,
      startedAt: now,
      endedAt: null,
      listenedSeconds: 0,
      completed: false,
      skipped: false,
    );

    _database.events.add(_currentEvent!);

    _updateArtistPreference(
      artist: artist,
      amount: 1.0,
    );

    await _save();
  }

  /// ==========================================================
  /// ACTUALIZAR PROGRESO
  /// ==========================================================
  ///
  /// Se puede llamar periódicamente desde el reproductor.
  ///
  /// positionSeconds = posición actual de reproducción.
  ///
  Future<void> updateProgress({
    required int positionSeconds,
    int? durationSeconds,
  }) async {
    await _ensureInitialized();

    final event = _currentEvent;

    if (event == null || _currentSongId == null) {
      return;
    }

    final song = _database.songs[_currentSongId!];

    if (song == null) {
      return;
    }

    final now = DateTime.now();

    final elapsed = now.difference(event.startedAt).inSeconds;

    final safeElapsed = max(
      0,
      elapsed,
    );

    event.listenedSeconds = max(
      event.listenedSeconds,
      min(
        safeElapsed,
        max(
          positionSeconds,
          0,
        ),
      ),
    );

    if (durationSeconds != null &&
        durationSeconds > 0) {
      song.durationSeconds = durationSeconds;

      final progress =
          positionSeconds / durationSeconds;

      if (progress >= 0.90) {
        event.completed = true;
      }
    }

    if (song.durationSeconds > 0) {
      final progress =
          positionSeconds / song.durationSeconds;

      if (progress >= 0.90) {
        event.completed = true;
      }
    }

    /// No guardamos en disco en cada segundo.
    ///
    /// El historial se guarda al detener/cambiar canción.
  }

  /// ==========================================================
  /// DETENER REPRODUCCIÓN
  /// ==========================================================
  ///
  /// Determina automáticamente:
  /// - cuánto escuchó
  /// - si terminó
  /// - si hizo skip
  ///
  Future<void> stopListening({
    int? positionSeconds,
    int? durationSeconds,
  }) async {
    await _ensureInitialized();

    final event = _currentEvent;

    if (event == null || _currentSongId == null) {
      return;
    }

    final now = DateTime.now();

    event.endedAt = now;

    final elapsed =
        now.difference(event.startedAt).inSeconds;

    var listenedSeconds = max(
      event.listenedSeconds,
      max(
        0,
        elapsed,
      ),
    );

    if (positionSeconds != null) {
      listenedSeconds = max(
        listenedSeconds,
        max(
          0,
          positionSeconds,
        ),
      );
    }

    event.listenedSeconds = listenedSeconds;

    final song = _database.songs[_currentSongId!];

    if (song != null) {
      final duration =
          durationSeconds ??
          song.durationSeconds;

      if (duration > 0) {
        song.durationSeconds = duration;

        final progress =
            listenedSeconds / duration;

        event.completed =
            event.completed ||
            progress >= 0.90;

        /// Skip:
        ///
        /// Menos del 20% escuchado.
        event.skipped =
            progress < 0.20 &&
            listenedSeconds >= 3;
      }

      song.totalListenedSeconds +=
          listenedSeconds;

      if (event.completed) {
        song.completedCount++;

        _updateArtistPreference(
          artist: song.artist,
          amount: 3.0,
        );
      }

      if (event.skipped) {
        song.skipCount++;

        _updateArtistPreference(
          artist: song.artist,
          amount: -1.5,
        );
      }

      _updateSongPreference(song);
    }

    _currentSongId = null;
    _currentStartedAt = null;
    _currentEvent = null;

    await _save();
  }

  /// ==========================================================
  /// MARCAR FAVORITO
  /// ==========================================================

  Future<void> setFavorite({
    required String songId,
    required bool favorite,
  }) async {
    await _ensureInitialized();

    final song = _database.songs[songId];

    if (song == null) return;

    song.favorite = favorite;

    if (favorite) {
      _updateSongPreference(song, amount: 8.0);

      _updateArtistPreference(
        artist: song.artist,
        amount: 4.0,
      );
    } else {
      _updateSongPreference(
        song,
        amount: -4.0,
      );
    }

    await _save();
  }

  /// ==========================================================
  /// REGISTRAR REPETICIÓN
  /// ==========================================================

  Future<void> registerReplay({
    required String songId,
  }) async {
    await _ensureInitialized();

    final song = _database.songs[songId];

    if (song == null) return;

    song.replayCount++;

    _updateSongPreference(
      song,
      amount: 5.0,
    );

    _updateArtistPreference(
      artist: song.artist,
      amount: 2.5,
    );

    await _save();
  }

  /// ==========================================================
  /// OBTENER CANCIONES APRENDIDAS
  /// ==========================================================

  Future<List<LearnedSong>> getKnownSongs() async {
    await _ensureInitialized();

    return _database.songs.values.toList();
  }

  /// ==========================================================
  /// REGISTRAR CANCIONES LOCALES
  /// ==========================================================
  ///
  /// Registra todas las canciones locales en la base de datos
  /// para que puedan aparecer como "no escuchadas".
  ///
  Future<void> registerLocalSongs(
    List<Map<String, dynamic>> songs,
  ) async {
    await _ensureInitialized();

    final now = DateTime.now();

    for (final songData in songs) {
      final id = songData['id']?.toString() ?? '';
      final title = songData['title']?.toString() ?? '';
      final artist = songData['artist']?.toString() ?? '';
      final thumbnail = songData['artworkUri']?.toString() ?? '';
      final duration = (songData['duration'] as num?)?.toInt() ?? 0;

      if (id.isEmpty) continue;

      /// Solo registrar si no existe
      if (!_database.songs.containsKey(id)) {
        _database.songs[id] = LearnedSong(
          id: id,
          title: title.isNotEmpty ? title : 'Sin título',
          artist: artist.isNotEmpty ? artist : 'Artista desconocido',
          thumbnail: thumbnail,
          source: 'local',
          durationSeconds: (duration / 1000).round(),
          playCount: 0,
          completedCount: 0,
          skipCount: 0,
          replayCount: 0,
          favorite: false,
          totalListenedSeconds: 0,
          preferenceScore: 0,
          firstPlayedAt: now,
          lastPlayedAt: now,
        );
      }
    }

    await _save();

    debugPrint(
      '[RecommendationService] Canciones locales registradas: ${songs.length}',
    );
  }

  /// ==========================================================
  /// CONTINÚA ESCUCHANDO
  /// ==========================================================

  Future<List<LearnedSong>> getContinueListening({
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final songs = _database.songs.values
        .where(
          (song) =>
              song.playCount > 0 &&
              song.skipCount < song.playCount,
        )
        .toList();

    songs.sort(
      (a, b) =>
          b.lastPlayedAt.compareTo(
            a.lastPlayedAt,
          ),
    );

    return songs.take(limit).toList();
  }

  /// ==========================================================
  /// MÁS ESCUCHADAS
  /// ==========================================================

  Future<List<LearnedSong>> getMostPlayed({
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final songs =
        _database.songs.values.toList();

    songs.sort(
      (a, b) {
        final scoreA =
            _calculateSongScore(a);

        final scoreB =
            _calculateSongScore(b);

        return scoreB.compareTo(scoreA);
      },
    );

    return songs.take(limit).toList();
  }

  /// ==========================================================
  /// FAVORITOS
  /// ==========================================================

  Future<List<LearnedSong>> getFavorites({
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final songs = _database.songs.values
        .where(
          (song) => song.favorite,
        )
        .toList();

    songs.sort(
      (a, b) =>
          b.lastPlayedAt.compareTo(
            a.lastPlayedAt,
          ),
    );

    return songs.take(limit).toList();
  }

  /// ==========================================================
  /// ARTISTAS FAVORITOS
  /// ==========================================================

  Future<List<ArtistPreference>>
      getTopArtists({
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final artists =
        _database.artists.values.toList();

    artists.sort(
      (a, b) =>
          b.score.compareTo(a.score),
    );

    return artists.take(limit).toList();
  }

  /// ==========================================================
  /// RECOMENDACIONES PRINCIPALES
  /// ==========================================================
  ///
  /// Genera recomendaciones usando:
  ///
  /// - frecuencia
  /// - recencia
  /// - finalizaciones
  /// - favoritos
  /// - repeticiones
  /// - skips
  /// - artistas
  ///
  Future<List<LearnedSong>> getRecommendations({
    int limit = 20,
  }) async {
    await _ensureInitialized();

    final songs =
        _database.songs.values.toList();

    if (songs.isEmpty) {
      return [];
    }

    final candidates = songs
        .map(
          (song) => _RecommendationCandidate(
            song: song,
            score: _calculateRecommendationScore(
              song,
            ),
          ),
        )
        .toList();

    candidates.sort(
      (a, b) =>
          b.score.compareTo(a.score),
    );

    /// Introducimos algo de variedad.
    ///
    /// No queremos que siempre aparezca
    /// exactamente la misma canción.
    final result = <LearnedSong>[];

    final usedArtists = <String>{};

    for (final candidate in candidates) {
      if (result.length >= limit) break;

      final artist =
          candidate.song.artist.trim();

      final normalizedArtist =
          artist.toLowerCase();

      /// Primera pasada:
      /// diversidad de artistas.
      if (!usedArtists.contains(
        normalizedArtist,
      )) {
        result.add(candidate.song);
        usedArtists.add(normalizedArtist);
      }
    }

    /// Segunda pasada:
    /// rellenar si todavía faltan.
    if (result.length < limit) {
      for (final candidate in candidates) {
        if (result.length >= limit) break;

        if (!result.contains(candidate.song)) {
          result.add(candidate.song);
        }
      }
    }

    return result;
  }

  /// ==========================================================
  /// DESCUBRIMIENTO
  /// ==========================================================
  ///
  /// Busca canciones que:
  /// - tengan poca reproducción
  /// - no hayan sido saltadas demasiado
  /// - pertenezcan a artistas que el usuario escucha
  ///
  /// Esto sirve como base para mezclar contenido nuevo
  /// con contenido conocido.
  ///
  Future<List<LearnedSong>> getDiscovery({
    int limit = 10,
    bool searchNew = true,
  }) async {
    await _ensureInitialized();

    final topArtists =
        await getTopArtists(
      limit: 20,
    );

    final artistScores = {
      for (final artist in topArtists)
        artist.name.toLowerCase():
            artist.score,
    };

    /// Canciones NUNCA escuchadas (prioridad alta)
    final neverPlayed = _database.songs.values.where(
      (song) =>
          song.playCount == 0 &&
          song.skipCount == 0,
    );

    /// Canciones escuchadas pocas veces (prioridad media)
    final rarelyPlayed = _database.songs.values.where(
      (song) =>
          song.playCount > 0 &&
          song.playCount <= 2 &&
          song.skipCount <= 1,
    );

    final scored = [...neverPlayed, ...rarelyPlayed].map(
      (song) {
        final artistScore =
            artistScores[
                  song.artist.toLowerCase()
                ] ??
                0;

        /// Bonificación extra para canciones nunca escuchadas
        final neverPlayedBonus = song.playCount == 0 ? 10.0 : 0.0;

        return _RecommendationCandidate(
          song: song,
          score:
              artistScore +
              song.completedCount * 2 +
              (song.favorite ? 5 : 0) +
              neverPlayedBonus,
        );
      },
    ).toList();

    scored.sort(
      (a, b) =>
          b.score.compareTo(a.score),
    );

    final localDiscovery = scored
        .take(limit)
        .map(
          (item) => item.song,
        )
        .toList();

    // Siempre buscar canciones nuevas de YouTube si está habilitado
    List<LearnedSong> youtubeSongs = [];
    if (searchNew) {
      try {
        final newSongs = await discoverNewSongs(
          limit: limit,
        );

        youtubeSongs = newSongs;
      } catch (e) {
        debugPrint(
          '[RecommendationService] Error en descubrimiento automático: $e',
        );
      }
    }

    // Mezclar: primero canciones locales, luego YouTube
    final result = [...localDiscovery, ...youtubeSongs].take(limit).toList();

    return result;
  }

  /// ==========================================================
  /// DESCUBRIMIENTO AUTOMÁTICO
  /// ==========================================================
  ///
  /// Busca automáticamente canciones nuevas en YouTube
  /// basadas en los artistas que el usuario escucha.
  ///
  Future<List<LearnedSong>> discoverNewSongs({
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final topArtists =
        await getTopArtists(
      limit: 5,
    );

    if (topArtists.isEmpty) {
      return [];
    }

    final discovered = <LearnedSong>[];

    for (final artist in topArtists) {
      if (discovered.length >= limit) break;

      try {
        final results =
            await YouTubeAudioService.instance.search(
          artist.name,
        );

        for (final result in results.take(3)) {
          if (discovered.length >= limit) break;

          final videoId = result.videoId;

          // Validar que el videoId sea válido (11 caracteres alfanuméricos)
          if (!_isValidYouTubeVideoId(videoId)) {
            debugPrint(
              '[RecommendationService] videoId inválido ignorado: $videoId',
            );
            continue;
          }

          // Verificar si ya existe en el historial
          if (_database.songs.containsKey(videoId)) {
            continue;
          }

          // Verificar si ya fue descubierta
          if (_discoveredSongs.containsKey(videoId)) {
            continue;
          }

          final discoveredSong = DiscoveredSong(
            videoId: videoId,
            title: result.title,
            artist: result.artist,
            thumbnail: result.thumbnail,
            durationSeconds: result.duration,
            discoveredAt: DateTime.now(),
          );

          _discoveredSongs[videoId] = discoveredSong;

          final learnedSong = LearnedSong(
            id: videoId,
            title: result.title,
            artist: result.artist,
            thumbnail: result.thumbnail,
            source: 'youtube',
            durationSeconds: result.duration,
            playCount: 0,
            completedCount: 0,
            skipCount: 0,
            replayCount: 0,
            favorite: false,
            totalListenedSeconds: 0,
            preferenceScore: 0,
            firstPlayedAt: DateTime.now(),
            lastPlayedAt: DateTime.now(),
          );

          _database.songs[videoId] = learnedSong;
          discovered.add(learnedSong);

          debugPrint(
            '[RecommendationService] Canción descubierta: ${result.title} por ${result.artist}',
          );
        }
      } catch (e) {
        debugPrint(
          '[RecommendationService] Error descubriendo canciones para ${artist.name}: $e',
        );
      }
    }

    if (discovered.isNotEmpty) {
      await _save();
      debugPrint(
        '[RecommendationService] ${discovered.length} canciones nuevas descubiertas de YouTube',
      );
    } else {
      debugPrint(
        '[RecommendationService] No se descubrieron canciones nuevas',
      );
    }

    return discovered;
  }

  /// ==========================================================
  /// MEZCLA PERSONALIZADA
  /// ==========================================================
  ///
  /// Crea una sesión mezclando:
  ///
  /// 60% canciones muy compatibles
  /// 25% canciones conocidas pero menos frecuentes
  /// 15% descubrimiento
  ///
  Future<List<LearnedSong>> createMix({
    int size = 20,
  }) async {
    await _ensureInitialized();

    final recommendations =
        await getRecommendations(
      limit: max(
        size,
        20,
      ),
    );

    final discovery =
        await getDiscovery(
      limit: max(
        size,
        10,
      ),
    );

    final favorites =
        await getFavorites(
      limit: max(
        size,
        10,
      ),
    );

    final result = <LearnedSong>[];

    void addIfValid(
      LearnedSong song,
    ) {
      if (result.length >= size) return;

      if (!result.any(
        (item) => item.id == song.id,
      )) {
        result.add(song);
      }
    }

    /// 60% recomendaciones.
    final recommendationCount =
        (size * 0.60).round();

    for (final song
        in recommendations.take(
      recommendationCount,
    )) {
      addIfValid(song);
    }

    /// 25% favoritos/conocidas.
    final favoriteCount =
        (size * 0.25).round();

    for (final song
        in favorites.take(
      favoriteCount,
    )) {
      addIfValid(song);
    }

    /// 15% descubrimiento.
    for (final song in discovery) {
      if (result.length >= size) break;

      addIfValid(song);
    }

    /// Rellenar si todavía faltan.
    final remaining = [
      ...recommendations,
      ...favorites,
      ...discovery,
    ];

    for (final song in remaining) {
      if (result.length >= size) break;

      addIfValid(song);
    }

    return result;
  }

  /// ==========================================================
  /// SESIÓN "PORQUE ESCUCHASTE..."
  /// ==========================================================

  Future<List<LearnedSong>>
      getBecauseYouListened({
    required String songId,
    int limit = 10,
  }) async {
    await _ensureInitialized();

    final source =
        _database.songs[songId];

    if (source == null) {
      return [];
    }

    final sourceArtist =
        source.artist.toLowerCase();

    final candidates =
        _database.songs.values
            .where(
              (song) =>
                  song.id != songId &&
                  song.artist
                      .toLowerCase() !=
                      sourceArtist,
            )
            .map(
              (song) {
                var score =
                    _calculateRecommendationScore(
                  song,
                );

                /// Si el usuario ya escucha al artista
                /// de la canción origen, aumenta compatibilidad.
                if (song.artist
                    .toLowerCase()
                    .contains(sourceArtist)) {
                  score += 10;
                }

                return _RecommendationCandidate(
                  song: song,
                  score: score,
                );
              },
            )
            .toList();

    candidates.sort(
      (a, b) =>
          b.score.compareTo(a.score),
    );

    return candidates
        .take(limit)
        .map(
          (item) => item.song,
        )
        .toList();
  }

  /// ==========================================================
  /// HISTORIAL
  /// ==========================================================

  Future<List<ListeningEvent>>
      getHistory({
    int limit = 50,
  }) async {
    await _ensureInitialized();

    final events =
        List<ListeningEvent>.from(
      _database.events,
    );

    events.sort(
      (a, b) =>
          b.startedAt.compareTo(
            a.startedAt,
          ),
    );

    return events.take(limit).toList();
  }

  /// ==========================================================
  /// ESTADÍSTICAS
  /// ==========================================================

  Future<RecommendationStats>
      getStats() async {
    await _ensureInitialized();

    final songs =
        _database.songs.values;

    final totalPlays = songs.fold<int>(
      0,
      (sum, song) =>
          sum + song.playCount,
    );

    final totalCompleted =
        songs.fold<int>(
      0,
      (sum, song) =>
          sum + song.completedCount,
    );

    final totalSkips =
        songs.fold<int>(
      0,
      (sum, song) =>
          sum + song.skipCount,
    );

    final totalListened =
        songs.fold<int>(
      0,
      (sum, song) =>
          sum +
          song.totalListenedSeconds,
    );

    final favoriteCount =
        songs.where(
      (song) => song.favorite,
    ).length;

    return RecommendationStats(
      knownSongs: songs.length,
      totalPlays: totalPlays,
      totalCompleted: totalCompleted,
      totalSkips: totalSkips,
      favoriteCount: favoriteCount,
      totalListenedSeconds:
          totalListened,
    );
  }

  /// ==========================================================
  /// APRENDIZAJE DE CANCIÓN
  /// ==========================================================

  void _updateSongPreference(
    LearnedSong song, {
    double? amount,
  }) {
    final delta =
        amount ??
        _calculateSongLearningValue(
          song,
        );

    song.preferenceScore += delta;

    if (song.preferenceScore < 0) {
      song.preferenceScore = 0;
    }
  }

  double _calculateSongLearningValue(
    LearnedSong song,
  ) {
    var score = 0.0;

    score += song.playCount * 1.5;

    score += song.completedCount * 4.0;

    score += song.replayCount * 5.0;

    score += song.favorite ? 8.0 : 0.0;

    score -= song.skipCount * 4.0;

    if (song.durationSeconds > 0) {
      final ratio =
          song.totalListenedSeconds /
              (song.durationSeconds *
                  max(song.playCount, 1));

      if (ratio >= 0.70) {
        score += 5.0;
      }
    }

    return score;
  }

  /// ==========================================================
  /// APRENDIZAJE DE ARTISTA
  /// ==========================================================

  void _updateArtistPreference({
    required String artist,
    required double amount,
  }) {
    final normalized =
        artist.trim();

    if (normalized.isEmpty) return;

    final key =
        normalized.toLowerCase();

    final existing =
        _database.artists[key];

    if (existing == null) {
      _database.artists[key] =
          ArtistPreference(
        name: normalized,
        score: max(
          amount,
          0,
        ),
      );
    } else {
      existing.score += amount;

      if (existing.score < 0) {
        existing.score = 0;
      }
    }
  }

  /// ==========================================================
  /// SCORE DE CANCIÓN
  /// ==========================================================

  double _calculateSongScore(
    LearnedSong song,
  ) {
    var score = 0.0;

    score +=
        song.playCount * 2.0;

    score +=
        song.completedCount * 5.0;

    score +=
        song.replayCount * 6.0;

    score +=
        song.favorite ? 12.0 : 0.0;

    score -=
        song.skipCount * 5.0;

    score +=
        song.preferenceScore;

    /// Recencia.
    final daysSincePlayed =
        DateTime.now()
            .difference(
              song.lastPlayedAt,
            )
            .inDays;

    final recencyBonus =
        max(
          0,
          14 - daysSincePlayed,
        );

    score +=
        recencyBonus * 0.5;

    return score;
  }

  /// ==========================================================
  /// SCORE DE RECOMENDACIÓN
  /// ==========================================================

  double _calculateRecommendationScore(
    LearnedSong song,
  ) {
    var score =
        _calculateSongScore(song);

    /// Penalizar demasiado las canciones
    /// que el usuario salta.
    if (song.skipCount > 0) {
      score -=
          song.skipCount * 3.0;
    }

    /// Premiar canciones que se completan.
    score +=
        song.completedCount * 3.0;

    /// Premiar artistas aprendidos.
    final artist =
        _database.artists[
          song.artist.toLowerCase()
        ];

    if (artist != null) {
      score +=
          artist.score * 0.8;
    }

    return score;
  }

  /// ==========================================================
  /// EXPORTAR DATOS
  /// ==========================================================

  Future<String> exportData() async {
    await _ensureInitialized();

    return jsonEncode(
      _database.toJson(),
    );
  }

  /// ==========================================================
  /// IMPORTAR DATOS
  /// ==========================================================

  Future<bool> importData(
    String json,
  ) async {
    try {
      final decoded =
          jsonDecode(json);

      if (decoded is! Map) {
        return false;
      }

      _database =
          RecommendationDatabase.fromJson(
        Map<String, dynamic>.from(
          decoded,
        ),
      );

      await _save();

      return true;
    } catch (e) {
      debugPrint(
        '[RecommendationService] '
        'Error importando datos: $e',
      );

      return false;
    }
  }

  /// ==========================================================
  /// BORRAR APRENDIZAJE
  /// ==========================================================

  Future<void> clearLearning() async {
    await _ensureInitialized();

    _database =
        RecommendationDatabase.empty();

    _currentSongId = null;
    _currentStartedAt = null;
    _currentEvent = null;

    await _save();

    debugPrint(
      '[RecommendationService] '
      'Aprendizaje eliminado.',
    );
  }

  /// ==========================================================
  /// ELIMINAR CANCIÓN INVÁLIDA
  /// ==========================================================

  Future<void> removeInvalidSong(String songId) async {
    await _ensureInitialized();

    if (_database.songs.containsKey(songId)) {
      _database.songs.remove(songId);
      await _save();

      debugPrint(
        '[RecommendationService] Canción inválida eliminada: $songId',
      );
    }
  }

  /// ==========================================================
  /// ID DE EVENTO
  /// ==========================================================

  String _createEventId() {
    return '${DateTime.now().microsecondsSinceEpoch}_'
        '${_random.nextInt(999999)}';
  }

  /// ==========================================================
  /// VALIDAR VIDEO ID DE YOUTUBE
  /// ==========================================================

  bool _isValidYouTubeVideoId(String videoId) {
    // Los videoIds de YouTube tienen 11 caracteres alfanuméricos
    // con algunos caracteres especiales permitidos (-, _)
    if (videoId.isEmpty) return false;
    if (videoId.length < 10 || videoId.length > 12) return false;

    // Verificar que sea alfanumérico con algunos caracteres especiales
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    return validPattern.hasMatch(videoId);
  }

  /// ==========================================================
  /// LIMPIAR CANCIONES INVÁLIDAS
  /// ==========================================================

  void _cleanupInvalidSongs() {
    final invalidIds = <String>[];

    for (final entry in _database.songs.entries) {
      final song = entry.value;

      // Solo validar canciones de YouTube
      if (song.source == 'youtube' && !_isValidYouTubeVideoId(song.id)) {
        invalidIds.add(entry.key);
        debugPrint(
          '[RecommendationService] VideoId inválido encontrado: ${song.id} - ${song.title}',
        );
      }
    }

    if (invalidIds.isNotEmpty) {
      for (final id in invalidIds) {
        _database.songs.remove(id);
      }

      debugPrint(
        '[RecommendationService] Eliminadas ${invalidIds.length} canciones con videoIds inválidos',
      );

      _save();
    } else {
      debugPrint(
        '[RecommendationService] No se encontraron videoIds inválidos',
      );
    }
  }
}

/// ============================================================
/// BASE DE DATOS LOCAL
/// ============================================================

class RecommendationDatabase {
  final Map<String, LearnedSong> songs;

  final Map<String, ArtistPreference> artists;

  final List<ListeningEvent> events;

  RecommendationDatabase({
    required this.songs,
    required this.artists,
    required this.events,
  });

  factory RecommendationDatabase.empty() {
    return RecommendationDatabase(
      songs: {},
      artists: {},
      events: [],
    );
  }

  factory RecommendationDatabase.fromJson(
    Map<String, dynamic> json,
  ) {
    final songsJson =
        json['songs'];

    final artistsJson =
        json['artists'];

    final eventsJson =
        json['events'];

    final songs =
        <String, LearnedSong>{};

    if (songsJson is Map) {
      for (final entry
          in songsJson.entries) {
        try {
          final value =
              entry.value;

          if (value is Map) {
            final song =
                LearnedSong.fromJson(
              Map<String, dynamic>.from(
                value,
              ),
            );

            songs[
                song.id] = song;
          }
        } catch (_) {}
      }
    }

    final artists =
        <String, ArtistPreference>{};

    if (artistsJson is Map) {
      for (final entry
          in artistsJson.entries) {
        try {
          final value =
              entry.value;

          if (value is Map) {
            final artist =
                ArtistPreference.fromJson(
              Map<String, dynamic>.from(
                value,
              ),
            );

            artists[
                    artist.name
                        .toLowerCase()] =
                artist;
          }
        } catch (_) {}
      }
    }

    final events =
        <ListeningEvent>[];

    if (eventsJson is List) {
      for (final item
          in eventsJson) {
        try {
          if (item is Map) {
            events.add(
              ListeningEvent.fromJson(
                Map<String, dynamic>.from(
                  item,
                ),
              ),
            );
          }
        } catch (_) {}
      }
    }

    /// Evitamos crecimiento infinito.
    ///
    /// Conservamos las últimas 1000 reproducciones.
    if (events.length > 1000) {
      events.sort(
        (a, b) =>
            b.startedAt.compareTo(
              a.startedAt,
            ),
      );

      events.removeRange(
        1000,
        events.length,
      );
    }

    return RecommendationDatabase(
      songs: songs,
      artists: artists,
      events: events,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'songs': {
        for (final entry
            in songs.entries)
          entry.key:
              entry.value.toJson(),
      },
      'artists': {
        for (final entry
            in artists.entries)
          entry.key:
              entry.value.toJson(),
      },
      'events': events
          .map(
            (event) =>
                event.toJson(),
          )
          .toList(),
    };
  }
}

/// ============================================================
/// CANCIÓN APRENDIDA
/// ============================================================

class LearnedSong {
  final String id;

  String title;

  String artist;

  String thumbnail;

  String source;

  int durationSeconds;

  int playCount;

  int completedCount;

  int skipCount;

  int replayCount;

  bool favorite;

  int totalListenedSeconds;

  double preferenceScore;

  DateTime firstPlayedAt;

  DateTime lastPlayedAt;

  LearnedSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.source,
    required this.durationSeconds,
    required this.playCount,
    required this.completedCount,
    required this.skipCount,
    this.replayCount = 0,
    required this.favorite,
    required this.totalListenedSeconds,
    this.preferenceScore = 0,
    required this.firstPlayedAt,
    required this.lastPlayedAt,
  });

  factory LearnedSong.fromJson(
    Map<String, dynamic> json,
  ) {
    return LearnedSong(
      id: json['id']?.toString() ?? '',
      title:
          json['title']?.toString() ?? '',
      artist:
          json['artist']?.toString() ?? '',
      thumbnail:
          json['thumbnail']?.toString() ?? '',
      source:
          json['source']?.toString() ??
              'unknown',
      durationSeconds:
          _safeInt(
        json['durationSeconds'],
      ),
      playCount:
          _safeInt(
        json['playCount'],
      ),
      completedCount:
          _safeInt(
        json['completedCount'],
      ),
      skipCount:
          _safeInt(
        json['skipCount'],
      ),
      replayCount:
          _safeInt(
        json['replayCount'],
      ),
      favorite:
          json['favorite'] == true,
      totalListenedSeconds:
          _safeInt(
        json['totalListenedSeconds'],
      ),
      preferenceScore:
          _safeDouble(
        json['preferenceScore'],
      ),
      firstPlayedAt:
          DateTime.tryParse(
                json['firstPlayedAt']
                    ?.toString() ??
                    '',
              ) ??
              DateTime.now(),
      lastPlayedAt:
          DateTime.tryParse(
                json['lastPlayedAt']
                    ?.toString() ??
                    '',
              ) ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'thumbnail': thumbnail,
      'source': source,
      'durationSeconds':
          durationSeconds,
      'playCount': playCount,
      'completedCount':
          completedCount,
      'skipCount': skipCount,
      'replayCount': replayCount,
      'favorite': favorite,
      'totalListenedSeconds':
          totalListenedSeconds,
      'preferenceScore':
          preferenceScore,
      'firstPlayedAt':
          firstPlayedAt.toIso8601String(),
      'lastPlayedAt':
          lastPlayedAt.toIso8601String(),
    };
  }
}

/// ============================================================
/// EVENTO DE ESCUCHA
/// ============================================================

class ListeningEvent {
  final String id;

  final String songId;

  final DateTime startedAt;

  DateTime? endedAt;

  int listenedSeconds;

  bool completed;

  bool skipped;

  ListeningEvent({
    required this.id,
    required this.songId,
    required this.startedAt,
    required this.endedAt,
    required this.listenedSeconds,
    required this.completed,
    required this.skipped,
  });

  factory ListeningEvent.fromJson(
    Map<String, dynamic> json,
  ) {
    return ListeningEvent(
      id: json['id']?.toString() ?? '',
      songId:
          json['songId']?.toString() ?? '',
      startedAt:
          DateTime.tryParse(
                json['startedAt']
                    ?.toString() ??
                    '',
              ) ??
              DateTime.now(),
      endedAt:
          DateTime.tryParse(
        json['endedAt']?.toString() ?? '',
      ),
      listenedSeconds:
          _safeInt(
        json['listenedSeconds'],
      ),
      completed:
          json['completed'] == true,
      skipped:
          json['skipped'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'songId': songId,
      'startedAt':
          startedAt.toIso8601String(),
      'endedAt':
          endedAt?.toIso8601String(),
      'listenedSeconds':
          listenedSeconds,
      'completed':
          completed,
      'skipped':
          skipped,
    };
  }
}

/// ============================================================
/// PREFERENCIA DE ARTISTA
/// ============================================================

class ArtistPreference {
  final String name;

  double score;

  ArtistPreference({
    required this.name,
    required this.score,
  });

  factory ArtistPreference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ArtistPreference(
      name:
          json['name']?.toString() ?? '',
      score:
          _safeDouble(
        json['score'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'score': score,
    };
  }
}

/// ============================================================
/// ESTADÍSTICAS
/// ============================================================

class RecommendationStats {
  final int knownSongs;

  final int totalPlays;

  final int totalCompleted;

  final int totalSkips;

  final int favoriteCount;

  final int totalListenedSeconds;

  const RecommendationStats({
    required this.knownSongs,
    required this.totalPlays,
    required this.totalCompleted,
    required this.totalSkips,
    required this.favoriteCount,
    required this.totalListenedSeconds,
  });

  Duration get totalListeningTime =>
      Duration(
        seconds: totalListenedSeconds,
      );
}

/// ============================================================
/// CANDIDATO DE RECOMENDACIÓN
/// ============================================================

class _RecommendationCandidate {
  final LearnedSong song;

  final double score;

  const _RecommendationCandidate({
    required this.song,
    required this.score,
  });
}

/// ============================================================
/// HELPERS JSON
/// ============================================================

int _safeInt(dynamic value) {
  if (value is int) return value;

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

double _safeDouble(dynamic value) {
  if (value is double) return value;

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

/// ============================================================
/// CANCIÓN DESCUBIERTA
/// ============================================================

class DiscoveredSong {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final int durationSeconds;
  final DateTime discoveredAt;

  DiscoveredSong({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.durationSeconds,
    required this.discoveredAt,
  });
}