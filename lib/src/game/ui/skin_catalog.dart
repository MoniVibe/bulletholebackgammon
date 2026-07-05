import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';

export 'package:bullethole_shared/bullethole_shared.dart'
    show BoardSkinOption, PieceSkinOption, PieceSkinRenderMode;

/// Backgammon-only skin catalog.
class SkinCatalog {
  static const BoardSkinOption backgammonBoardClassic = BoardSkinOption(
    id: 'bg_classic',
    label: 'Backgammon Classic',
    assetPath: AppAssets.backgammonBoardClassic,
    tintOverlay: Color(0x12000000),
  );

  static const BoardSkinOption backgammonBoardPainted = BoardSkinOption(
    id: 'bg_painted',
    label: 'Modern Painted',
    assetPath: AppAssets.backgammonBoardPainted,
    isPremium: true,
  );

  static const List<BoardSkinOption> backgammonBoardSkins = <BoardSkinOption>[
    backgammonBoardClassic,
    backgammonBoardPainted,
  ];

  static const PieceSkinOption backgammonPiecesRoyal = PieceSkinOption(
    id: 'bg_royal',
    label: 'Royal Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.whiteCoin,
    blackAssetPath: AppAssets.blackCoin,
  );

  static const PieceSkinOption backgammonPiecesRuby = PieceSkinOption(
    id: 'bg_ruby',
    label: 'Ruby Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.redCoin,
    blackAssetPath: AppAssets.redCoin,
  );

  static const PieceSkinOption backgammonPiecesNeon = PieceSkinOption(
    id: 'bg_neon',
    label: 'Neon Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.whiteCoin,
    blackAssetPath: AppAssets.blackCoin,
    tintColor: Color(0xFF00E5FF),
    isPremium: true,
  );

  static const PieceSkinOption backgammonPiecesMinimal = PieceSkinOption(
    id: 'bg_minimal',
    label: 'Minimal Chips',
    mode: PieceSkinRenderMode.flat,
  );

  static const List<PieceSkinOption> backgammonPieceSkins = <PieceSkinOption>[
    backgammonPiecesRuby,
    backgammonPiecesRoyal,
    backgammonPiecesNeon,
    backgammonPiecesMinimal,
  ];

  static String get defaultBackgammonBoardSkinId => backgammonBoardPainted.id;
  static String get defaultBackgammonPieceSkinId => backgammonPiecesRoyal.id;

  static BoardSkinOption backgammonBoardById(String id) {
    return backgammonBoardSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => backgammonBoardClassic,
    );
  }

  static PieceSkinOption backgammonPieceById(String id) {
    return backgammonPieceSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => backgammonPiecesRoyal,
    );
  }
}
