import 'package:flutter/material.dart';

import '../music_player.dart';
import 'artist_album_discovery_section.dart';

class ArtistsSection extends StatelessWidget {
  const ArtistsSection({
    super.key,
    required this.player,
    required this.songs,
    this.searchText = '',
  });

  final MusicPlayerController player;
  final List<Song> songs;
  final String searchText;

  @override
  Widget build(BuildContext context) => ArtistAlbumDiscoverySection(
    player: player,
    songs: songs,
    searchText: searchText,
    showArtists: true,
  );
}
