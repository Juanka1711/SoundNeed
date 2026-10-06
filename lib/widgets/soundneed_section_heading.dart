import 'package:flutter/material.dart';

/// Consistent section title and compact context badge for library screens.
class SoundNeedSectionHeading extends StatelessWidget {
  const SoundNeedSectionHeading({
    super.key,
    required this.title,
    this.detail,
    this.accent = const Color(0xFF8B5CF6),
  });

  final String title;
  final String? detail;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent, Color.lerp(accent, Colors.white, .30)!],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -.35,
          ),
        ),
      ),
      if (detail != null && detail!.trim().isNotEmpty) ...[
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: .23)),
            ),
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color.lerp(accent, Colors.white, .35),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
