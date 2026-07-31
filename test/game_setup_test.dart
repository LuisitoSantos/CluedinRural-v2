import 'package:cluedin_rural_murdoku/game/game_models.dart';
import 'package:cluedin_rural_murdoku/game/game_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asigna posiciones válidas y equipos equilibrados', () {
    final players = List.generate(26, (i) => GamePlayer(id: '$i', name: 'Jugador $i'));
    final tiles = [
      for (var column = 0; column < 33; column++)
        for (var row = 0; row < 21; row++)
          MapTile(name: '$column-$row', column: column, row: row, type: 'ground', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
      const MapTile(name: 'blocked', column: 40, row: 0, type: 'rock', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
    ];
    final result = GameSetup().initialize(players: players, tiles: tiles);

    expect(result, hasLength(26));
    expect(result.map((player) => player.position!.name).toSet(), hasLength(26));
    expect(result.map((player) => player.position!.column).toSet(), hasLength(26));
    expect(result.any((player) => player.position!.name == 'blocked'), isFalse);
    final sizes = Team.values
        .map((team) => result.where((player) => player.team == team).length)
        .toList();
    expect(sizes.reduce((a, b) => a - b).abs(), lessThanOrEqualTo(1));
  });
}
