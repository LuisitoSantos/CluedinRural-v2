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
    final surroundings = {
      'arriba': tile.up,
      'abajo': tile.down,
      'izquierda': tile.left,
      'derecha': tile.right,
    };
    final clues = <String>[
      'Un jugador esta sobre ${_terrainLabel(tile.type)}${_isOutdoor(tile.type) ? ', en el exterior' : ', en el interior'}.',
    ];
    final trees = surroundings.values.where((type) => type == 'tree').length;
    if (trees >= 2) clues.add('Tiene arboles en al menos dos lados.');

    const barriers = {'wall', 'fence'};
    final vertical = barriers.contains(tile.up) || barriers.contains(tile.down);
    final horizontal = barriers.contains(tile.left) || barriers.contains(tile.right);
    if (vertical && horizontal) clues.add('Esta en una esquina delimitada por pared o valla.');

    const plainGround = {'ground', 'floor', 'grass'};
    if (surroundings.values.every(plainGround.contains)) {
      clues.add('Solo tiene terreno libre alrededor.');
    }

    for (final entry in surroundings.entries) {
      final label = _nearbyLabel(entry.value);
      if (label != null) clues.add('${_directionLabel(entry.key)} hay $label.');
    }

    if (clues.length == 1) clues.add('No tiene objetos destacados justo al lado.');
    return clues.join(' ');
  }

  bool _isOutdoor(String type) => {'ground', 'grass', 'rock', 'tree'}.contains(type);

  String _terrainLabel(String type) => switch (type) {
        'ground' => 'tierra',
        'grass' => 'hierba',
        'floor' => 'suelo de la casa',
        'bathroom' => 'suelo de bano',
        'bed' => 'una cama',
        'couch' => 'un sofa',
        _ => type.isEmpty ? 'un terreno desconocido' : type,
      };

  String? _nearbyLabel(String type) => switch (type) {
        'tree' => 'un arbol',
        'rock' => 'una roca',
        'wall' => 'una pared',
        'fence' => 'una valla',
        'door' => 'una puerta',
        'window' => 'una ventana',
        'table' => 'una mesa',
        'shower' => 'una ducha',
        'bed' => 'una cama',
        'closet' => 'un armario',
        'couch' => 'un sofa',
        'worktop' => 'una encimera',
        _ => null,
      };

  String _directionLabel(String direction) => switch (direction) {
        'arriba' => 'Encima',
        'abajo' => 'Debajo',
        'izquierda' => 'A su izquierda',
        'derecha' => 'A su derecha',
        _ => 'Cerca',
      };
}
