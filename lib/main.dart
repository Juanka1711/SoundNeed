import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'music_player.dart';
import 'music_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_player.channel.audio',
    androidNotificationChannelName: 'SoundNeed',
    androidNotificationChannelDescription:
        'Controles de reproducción de SoundNeed',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
  );

  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  // ============================================================
  // COLORES DE SOUNDNEED
  // ============================================================

  static const Color background = Color(0xFF0B0B12);
  static const Color surface = Color(0xFF151522);
  static const Color card = Color(0xFF1D1D2B);
  static const Color primary = Color(0xFF8B5CF6);
  static const Color secondary = Color(0xFFEC4899);
  static const Color favorite = Color(0xFFF43F5E);
  static const Color textSecondary = Color(0xFFA1A1AA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SoundNeed',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          surface: surface,
        ),
        useMaterial3: true,

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),

        cardTheme: const CardThemeData(
          color: card,
        ),

        sliderTheme: SliderThemeData(
          activeTrackColor: primary,
          thumbColor: secondary,
          inactiveTrackColor: Colors.white12,
          overlayColor: primary.withOpacity(0.15),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primary,
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: card,
          contentTextStyle: const TextStyle(
            color: Colors.white,
          ),
          actionTextColor: secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: const TextStyle(
            color: textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: primary,
              width: 1.5,
            ),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: const SoundNeedHome(),
    );
  }
}

class SoundNeedHome extends StatefulWidget {
  const SoundNeedHome({super.key});

  @override
  State<SoundNeedHome> createState() => _SoundNeedHomeState();
}

class _SoundNeedHomeState extends State<SoundNeedHome> {
  late final MusicPlayerController _player;

  @override
  void initState() {
    super.initState();
    _player = MusicPlayerController();
    _player.initialize();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MusicHomePage(player: _player);
  }
}
