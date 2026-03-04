import 'package:bulletholebackgammon/src/game/ui/skin_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backgammon board catalog exposes expected ids', () {
    final ids = SkinCatalog.backgammonBoardSkins.map((skin) => skin.id).toSet();
    expect(ids, containsAll(<String>{'bg_classic', 'bg_painted'}));
  });

  test('backgammon piece catalog exposes expected ids', () {
    final ids = SkinCatalog.backgammonPieceSkins.map((skin) => skin.id).toSet();
    expect(ids, containsAll(<String>{'bg_royal', 'bg_ruby', 'bg_minimal'}));
  });

  test('ruby chip skin applies ruby asset for both sides', () {
    final ruby = SkinCatalog.backgammonPieceById('bg_ruby');
    expect(ruby.whiteAssetPath, isNotNull);
    expect(ruby.blackAssetPath, isNotNull);
    expect(ruby.whiteAssetPath, ruby.blackAssetPath);
  });
}
