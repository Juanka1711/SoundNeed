import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'services/audio_handler.dart';

late final SoundNeedAudioHandler soundNeedAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  soundNeedAudioHandler = await AudioService.init<SoundNeedAudioHandler>(
    builder: SoundNeedAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.channel.audio',
      androidNotificationChannelName: 'SoundNeed',
      androidNotificationChannelDescription:
          'Controles de reproducción de SoundNeed',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(MusicPlayerApp(audioHandler: soundNeedAudioHandler));
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key, required this.audioHandler});

  final SoundNeedAudioHandler audioHandler;

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
          elevation: 0,
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: Colors.white10),
          ),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -.3,
          ),
          contentTextStyle: const TextStyle(
            color: textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),

        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          modalBackgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 20,
          showDragHandle: true,
          dragHandleColor: Colors.white38,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            side: BorderSide(color: Colors.white10),
          ),
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 14,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 14),
        ),

        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: .08),
          thickness: 1,
          space: 1,
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
      home: SoundNeedHome(audioHandler: audioHandler),
    );
  }
}

class SoundNeedHome extends StatefulWidget {
  const SoundNeedHome({super.key, required this.audioHandler});

  final SoundNeedAudioHandler audioHandler;

  @override
  State<SoundNeedHome> createState() => _SoundNeedHomeState();
}

class _SoundNeedHomeState extends State<SoundNeedHome> {
  late final MusicPlayerController _player;

  @override
  void initState() {
    super.initState();
    _player = MusicPlayerController(audioHandler: widget.audioHandler);
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
