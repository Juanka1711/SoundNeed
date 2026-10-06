import 'package:flutter/material.dart';

import '../music_player.dart';
import '../services/artwork_palette.dart';
import 'artist_album_discovery_section.dart';

class ArtistsSection extends StatelessWidget {
  const ArtistsSection({
    super.key,
    required this.player,
    required this.songs,
    required this.palette,
    this.searchText = '',
  });

  final MusicPlayerController player;
  final List<Song> songs;
  final ArtworkPalette palette;
  final String searchText;

  @override
  Widget build(BuildContext context) => ArtistAlbumDiscoverySection(
    player: player,
    songs: songs,
    palette: palette,
    searchText: searchText,
    showArtists: true,
  );
}
