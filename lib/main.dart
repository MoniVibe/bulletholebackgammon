import 'package:flutter/material.dart';

import 'src/game/engine/backgammon_online_controller.dart';
import 'src/game/ui/game_screen.dart';

void main() {
  runApp(const BulletholeBackgammonApp());
}

class BulletholeBackgammonApp extends StatelessWidget {
  const BulletholeBackgammonApp({super.key, this.onlineControllerFactory});

  /// Test-only seam forwarded to [GameScreen] so widget tests can supply a
  /// controller with a stubbed HTTP client. Null in production.
  @visibleForTesting
  final BackgammonOnlineController Function()? onlineControllerFactory;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1B3F59);
    const secondary = Color(0xFFE6A23C);
    const surface = Color(0xFFF4F2EE);
    const onSurface = Color(0xFF191A1C);

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    return MaterialApp(
      title: 'Bullethole Sheshbesh',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme
            .apply(
              fontFamily: 'Sora',
              bodyColor: onSurface,
              displayColor: onSurface,
            )
            .copyWith(
              titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
              headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
        cardTheme: CardThemeData(
          color: const Color(0xF2FFFFFF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Colors.black.withValues(alpha: 0.07),
              width: 1,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xCCFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          ),
        ),
      ),
      home: GameScreen(onlineControllerFactory: onlineControllerFactory),
    );
  }
}
