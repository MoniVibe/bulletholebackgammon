/// Centralized asset registry for the visual layer.
///
/// Reasoning:
/// - Keeps asset paths in one place to avoid hard-coded strings across widgets.
/// - Makes it easy to swap art drops without touching game logic.
class AppAssets {
  static const String appBackground = 'assets/generated/ui/background.png';
  static const String backgammonBoardClassic =
      'assets/generated/sheshbesh/backgammon_board_classic.png';
  static const String backgammonBoardPainted = 'assets/Backgammonboard.png.png';
  static const String horizontalTimeBar =
      'assets/generated/ui/time_bar_horizontal.png';
  static const String verticalTimeBar =
      'assets/generated/ui/time_bar_vertical.png';
  static const String horizontalTimeBarAccent =
      'assets/generated/ui/time_bar_horizontal_red.png';
  static const String verticalTimeBarAccent =
      'assets/generated/ui/time_bar_vertical_gold.png';

  static const String settingsIcon = 'assets/Settings.png';
  static const String newGameIcon = 'assets/Newgame.png';
  static const String rematchIcon = 'assets/rematch.png';
  static const String feedbackIcon = 'assets/feedback.png';
  static const String whiteCoin = 'assets/generated/sheshbesh/white_coin.png';
  static const String blackCoin = 'assets/generated/sheshbesh/black_coin.png';
  static const String redCoin = 'assets/generated/sheshbesh/red_coin.png';

  static const Map<int, String> diceFaces = <int, String>{
    1: 'assets/generated/sheshbesh/dice_1.png',
    2: 'assets/generated/sheshbesh/dice_2.png',
    3: 'assets/generated/sheshbesh/dice_3.png',
    4: 'assets/generated/sheshbesh/dice_4.png',
    5: 'assets/generated/sheshbesh/dice_5.png',
    6: 'assets/generated/sheshbesh/dice_6.png',
  };

  static String? diceFaceAsset(int face) => diceFaces[face];
}
