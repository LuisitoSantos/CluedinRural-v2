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
    required Map<String, CharacterProfile> charactersByName,
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

    final characterNames = {
      for (final entry in charactersByName.entries) entry.key.toLowerCase(): entry.value,
    };
    for (final player in players.where((player) => !player.isFake)) {
      if (!characterNames.containsKey(player.name.trim().toLowerCase())) {
        throw StateError('No existe ningun personaje llamado "${player.name}" en el fichero de personajes.');
      }
    }

    final shuffledPlayers = [...players]..shuffle(_random);
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
      final player = shuffledPlayers[index];
      final character = characterNames[player.name.trim().toLowerCase()];
      final team = player.isFake ? Team.values[_random.nextInt(Team.values.length)] : character!.team;
      placed.add(player.copyWith(
        team: team,
        position: position,
        characterName: player.isFake ? 'Personaje ficticio ${index + 1}' : character!.name,
        // Equipo y familia son la misma agrupación de juego. Los ficticios
        // usan la familia correspondiente al color que reciben en el sorteo.
        familyName: team.familyName,
        clue: _clueFor(position),
      ));
    }
    return placed;
  }

  GameMystery selectMystery(List<GamePlayer> players) {
    if (players.length < 3) {
      throw StateError('Se necesitan al menos 3 jugadores para elegir al ladron y sus dos complices.');
    }
    final suspects = [...players]..shuffle(_random);
    return GameMystery(
      thiefId: suspects[0].id,
      accompliceIds: [suspects[1].id, suspects[2].id],
    );
  }

  List<Map<String, dynamic>> assignSecondaryMissions({
    required List<GamePlayer> players,
    required List<GamePlayer> targets,
    required List<SecondaryMissionDefinition> missions,
    required GameAreaLookup areas,
  }) {
    if (missions.length < 5) throw StateError('No hay suficientes misiones secundarias.');
    if (targets.length < players.length * 5) {
      throw StateError('No hay suficientes personajes para asociar una pista única a cada misión.');
    }
    final result = <Map<String, dynamic>>[];
    final availableTargets = [...targets]..shuffle(_random);
    for (final player in players) {
      final deck = [...missions]..shuffle(_random);
      for (var index = 0; index < 5; index++) {
        final mission = deck[index];
        final targetIndex = availableTargets.indexWhere((target) => target.team != player.team);
        if (targetIndex < 0) {
          throw StateError('No hay personajes de otros equipos suficientes para repartir las pistas únicas.');
        }
        final target = availableTargets.removeAt(targetIndex);
        final clue = _secondaryClueFor(target, areas);
        result.add({
          'participant_id': player.id,
          'participant_type': player.isFake ? 'fake' : 'real',
          'mission_number': index + 1,
          'mission_id': mission.id,
          'mission_level': mission.level,
          'mission_action': mission.action,
          'clue': clue.text,
          'target_participant_id': target.id,
          'clue_type': clue.type,
        });
      }
    }
    return result;
  }

  _SecondaryClue _secondaryClueFor(GamePlayer target, GameAreaLookup areas) {
    final position = target.position!;
    final room = areas.roomsFor(position.name).firstOrNull;
    final options = <_SecondaryClue>[
      if (room != null) _SecondaryClue(type: 'room', text: 'Hay un jugador en la habitación $room.'),
      _SecondaryClue(type: 'column', text: 'Hay un jugador en la columna ${position.name.substring(1)}.'),
      _SecondaryClue(type: 'row', text: 'Hay un jugador en la fila ${position.name.substring(0, 1)}.'),
      _SecondaryClue(type: 'location', text: 'Hay un jugador cuya ubicación cumple esto: ${target.clue}'),
    ];
    return options[_random.nextInt(options.length)];
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

class _SecondaryClue {
  const _SecondaryClue({required this.type, required this.text});

  final String type;
  final String text;
}

class CharacterProfile {
  const CharacterProfile({required this.name, required this.team, required this.family});

  final String name;
  final Team team;
  final String family;

  factory CharacterProfile.fromJson(String name, Map<String, dynamic> json) {
    final teamLabel = json['Equipo'] as String?;
    final family = json['Familia'] as String?;
    final team = Team.values.where((team) => team.label.toLowerCase() == teamLabel?.toLowerCase()).firstOrNull;
    if (team == null || family == null || family.trim().isEmpty) {
      throw FormatException('El personaje "$name" no tiene equipo o familia validos.');
    }
    return CharacterProfile(name: name, team: team, family: family);
  }
}
