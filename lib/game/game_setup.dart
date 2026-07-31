import 'dart:math';

import 'game_models.dart';

const blockedTileTypes = <String>{
  'rock', 'table', 'closet', 'tree', 'shower', 'worktop','empty'
};

class GameSetup {
  GameSetup({Random? random}) : _random = random ?? Random();

  final Random _random;

  List<GamePlayer> initialize({
    required List<GamePlayer> players,
    required List<MapTile> tiles,
  }) {
    if (players.isEmpty) return const [];
    final availableByColumn = <int, List<MapTile>>{};
    for (final tile in tiles) {
      if (!blockedTileTypes.contains(tile.type)) {
        availableByColumn.putIfAbsent(tile.column, () => []).add(tile);
      }
    }
    if (availableByColumn.length < players.length) {
      throw StateError('No hay suficientes columnas disponibles para ${players.length} jugadores.');
    }

    final shuffledPlayers = [...players]..shuffle(_random);
    final characters = List.generate(players.length, (index) => 'Personaje ${index + 1}')..shuffle(_random);
    const roles = ['Rol 1', 'Rol 2', 'Rol 3', 'Rol 4', 'Rol 5'];
    final columns = availableByColumn.keys.toList()..shuffle(_random);
    final rowUse = <int, int>{};
    final placed = <GamePlayer>[];
    for (var index = 0; index < shuffledPlayers.length; index++) {
      final choices = availableByColumn[columns[index]]!;
      final minimumUse = choices.map((tile) => rowUse[tile.row] ?? 0).reduce(min);
      final leastUsedChoices = choices
          .where((tile) => (rowUse[tile.row] ?? 0) == minimumUse)
          .toList()..shuffle(_random);
      final position = leastUsedChoices.first;
      rowUse.update(position.row, (count) => count + 1, ifAbsent: () => 1);
      placed.add(shuffledPlayers[index].copyWith(
        team: Team.values[index % Team.values.length],
        position: position,
        characterName: characters[index],
        roleName: roles[index % roles.length],
        clue: _clueFor(position),
      ));
    }
    return placed;
  }

  String _clueFor(MapTile tile) {
    final surroundings = [tile.up, tile.down, tile.left, tile.right];
    if (surroundings.where((type) => type == 'tree').length >= 2) {
      return 'Un jugador esta rodeado de arboles.';
    }
    final isWallOrFence = {
      'wall', 'fence',
    };
    final vertical = isWallOrFence.contains(tile.up) || isWallOrFence.contains(tile.down);
    final horizontal = isWallOrFence.contains(tile.left) || isWallOrFence.contains(tile.right);
    if (vertical && horizontal) return 'Un jugador esta en una esquina de la casa o del exterior.';
    if (surroundings.every((type) => {'ground', 'floor', 'grass'}.contains(type))) {
      return 'Un jugador solo tiene suelo alrededor.';
    }
    if (surroundings.contains('shower')) return 'Un jugador esta junto a una ducha.';
    if (surroundings.contains('table')) return 'Un jugador esta junto a una mesa.';
    if (surroundings.contains('rock')) return 'Un jugador esta junto a una roca.';
    if (surroundings.contains('bed')) return 'Un jugador esta junto a una cama.';
    return 'Un jugador esta en una zona abierta del mapa.';
  }
}
