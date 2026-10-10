import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'music_player.dart';
import 'playlist_manager.dart' show songKey;

/// A single framed cover that composes the first four tracks into one artwork.
class PlaylistArtwork extends StatefulWidget {
  const PlaylistArtwork({
    super.key,
    required this.player,
    required this.songs,
    required this.icon,
    required this.accent,
  });

  final MusicPlayerController player;
  final List<Song> songs;
  final IconData icon;
  final Color accent;

  @override
  State<PlaylistArtwork> createState() => _PlaylistArtworkState();
}

class _PlaylistArtworkState extends State<PlaylistArtwork> {
  late List<Song> _covers;
  late List<Future<Uint8List?>> _artwork;
  late int _artworkRevision;

  @override
  void initState() {
    super.initState();
    _artworkRevision = widget.player.artworkRevision;
    widget.player.addListener(_onPlayerChanged);
    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant PlaylistArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      widget.player.addListener(_onPlayerChanged);
      _artworkRevision = widget.player.artworkRevision;
    }
    final oldKeys = oldWidget.songs.take(4).map(songKey).join('|');
    final newKeys = widget.songs.take(4).map(songKey).join('|');
    if (oldWidget.player != widget.player || oldKeys != newKeys) {
      _loadArtwork();
    }
  }

  void _onPlayerChanged() {
    if (_artworkRevision == widget.player.artworkRevision) return;
    _artworkRevision = widget.player.artworkRevision;
    if (!mounted) return;
    setState(_loadArtwork);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _loadArtwork() {
    _covers = widget.songs.take(4).toList(growable: false);
    _artwork = _covers
        .map((song) => widget.player.loadArtwork(song))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.accent.withValues(alpha: .32),
              const Color(0xFF151522),
              widget.accent.withValues(alpha: .14),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _covers.isEmpty
              ? Center(
                  child: Icon(widget.icon, color: Colors.white70, size: 42),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final halfWidth = constraints.maxWidth / 2;
                    final halfHeight = constraints.maxHeight / 2;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          width: halfWidth,
                          height: halfHeight,
                          child: _coverTile(0),
                        ),
                        Positioned(
                          left: halfWidth,
                          top: 0,
                          width: halfWidth,
                          height: halfHeight,
                          child: _coverTile(1),
                        ),
                        Positioned(
                          left: 0,
                          top: halfHeight,
                          width: halfWidth,
                          height: halfHeight,
                          child: _coverTile(2),
                        ),
                        Positioned(
                          left: halfWidth,
                          top: halfHeight,
                          width: halfWidth,
                          height: halfHeight,
                          child: _coverTile(3),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _coverTile(int index) {
    final coverIndex = index % _covers.length;
    return FutureBuilder<Uint8List?>(
      future: _artwork[coverIndex],
      builder: (context, snapshot) {
        final image = snapshot.data;
        return image != null
            ? Image.memory(
                image,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              )
            : ColoredBox(
                color: widget.accent.withValues(alpha: .22),
                child: Icon(
                  Icons.music_note_rounded,
                  color: Colors.white.withValues(alpha: .72),
                ),
              );
      },
    );
  }
}
