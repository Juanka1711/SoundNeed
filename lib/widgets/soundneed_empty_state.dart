import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Calm, consistent empty and permission state used across SoundNeed screens.
class SoundNeedEmptyState extends StatelessWidget {
  const SoundNeedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent = const Color(0xFF8B5CF6),
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 430),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, AppColors.card, .78)!,
            AppColors.card.withValues(alpha: .88),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .16),
              border: Border.all(color: accent.withValues(alpha: .32)),
            ),
            child: Icon(icon, size: 29, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
