import 'package:flutter/material.dart';
import '../app_colors.dart';

class FoldersSection extends StatelessWidget {
  const FoldersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildComingSoon(
      Icons.folder_outlined,
      'Carpetas',
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
