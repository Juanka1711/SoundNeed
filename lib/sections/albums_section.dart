import 'package:flutter/material.dart';
import '../app_colors.dart';

class AlbumsSection extends StatelessWidget {
  const AlbumsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildComingSoon(
      Icons.album_outlined,
      'Álbumes',
    );
  }

  Widget _buildComingSoon(
    IconData icon,
    String title,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 65,
              color: Colors.white38,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta sección estará disponible próximamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
