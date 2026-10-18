import 'package:flutter/material.dart';

import '../music_player.dart';

bool isLocalMusic(Song song) => !song.isOnline && !song.isPodcast;

class LocalMusicBadge extends StatelessWidget {
  const LocalMusicBadge({super.key, this.color = Colors.white70});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: ShapeDecoration(
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: .7))),
    ),
    child: Text(
      'Local',
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 9,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
      ),
    ),
  );
}
