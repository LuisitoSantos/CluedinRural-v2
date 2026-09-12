import 'package:cluedin_rural_murdoku/game/game_models.dart';
import 'package:cluedin_rural_murdoku/game/game_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asigna posiciones válidas y un equipo aleatorio a los ficticios', () {
    final players = List.generate(26, (i) => GamePlayer(id: '$i', name: 'Jugador $i', isFake: true));
    final tiles = [
      for (var column = 0; column < 33; column++)
        for (var row = 0; row < 21; row++)
          MapTile(name: '$column-$row', column: column, row: row, type: 'ground', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
      const MapTile(name: 'blocked', column: 40, row: 0, type: 'rock', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
    ];
    final result = GameSetup().initialize(players: players, tiles: tiles, charactersByName: const {});

    expect(result, hasLength(26));
    expect(result.map((player) => player.position!.name).toSet(), hasLength(26));
    expect(result.map((player) => player.position!.column).toSet(), hasLength(26));
    expect(result.any((player) => player.position!.name == 'blocked'), isFalse);
    expect(result.every((player) => player.team != null), isTrue);
    expect(result.every((player) => player.familyName == player.team!.familyName), isTrue);
  });

  test('usa el personaje, equipo y familia predefinidos para jugadores reales', () {
    final tiles = [
      const MapTile(name: '0-0', column: 0, row: 0, type: 'ground', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
      const MapTile(name: '1-0', column: 1, row: 0, type: 'ground', up: 'ground', down: 'ground', left: 'ground', right: 'ground'),
    ];
    const lewis = CharacterProfile(name: 'Lewis', team: Team.green, family: "O'Doherty");
    const camilo = CharacterProfile(name: 'Camilo', team: Team.red, family: 'Rossi');

    final result = GameSetup().initialize(
      players: const [GamePlayer(id: 'lewis', name: 'Lewis'), GamePlayer(id: 'camilo', name: 'Camilo')],
      tiles: tiles,
      charactersByName: const {'Lewis': lewis, 'Camilo': camilo},
    );

    final byName = {for (final player in result) player.name: player};
    expect(byName['Lewis']!.characterName, 'Lewis');
    expect(byName['Lewis']!.team, Team.green);
    expect(byName['Lewis']!.familyName, "O'Doherty");
    expect(byName['Camilo']!.team, Team.red);
    expect(byName['Camilo']!.familyName, 'Rossi');
  });

  test('elige un ladron y dos complices distintos', () {
    const players = [
      GamePlayer(id: 'a', name: 'A', isFake: true),
      GamePlayer(id: 'b', name: 'B', isFake: true),
      GamePlayer(id: 'c', name: 'C', isFake: true),
      GamePlayer(id: 'd', name: 'D', isFake: true),
    ];

    final mystery = GameSetup().selectMystery(players);

    expect(mystery.accompliceIds, hasLength(2));
    expect(mystery.suspectIds.toSet(), hasLength(3));
    expect(mystery.suspectIds.every((id) => players.any((player) => player.id == id)), isTrue);
    expect(mystery.secretWord, isNotEmpty);
  });

  test('el misterio conserva las tres estancias aunque se repitan', () {
    const mystery = GameMystery(
      thiefId: 'a',
      accompliceIds: ['b', 'c'],
      suspectRoomNames: ['Room1', 'Room1', 'Room3'],
    );

    expect(mystery.toJson()['suspect_room_names'], ['Room1', 'Room1', 'Room3']);
  });

  test('localiza cuadrantes y estancias de las casillas', () {
    final areas = GameAreaLookup.fromJson(
      quadrants: {
        'A': {
          'belongBoxes': [
            ['A1'],
          ],
        },
      },
      rooms: {
        'Kitchen': {
          'belongBoxes': [
            ['A1'],
          ],
        },
      },
    );

    expect(areas.quadrantFor('A1'), 'A');
    expect(areas.roomsFor('A1'), ['Kitchen']);
  });

  test('las misiones secundarias dan una sola pista de personajes de otro equipo', () {
    final players = [
      for (var index = 0; index < 5; index++)
        GamePlayer(
          id: 'red-$index',
          name: 'Rojo $index',
          isFake: true,
          team: Team.red,
          position: BoardPosition(name: 'A${index + 1}', column: index + 1, row: 0),
          clue: 'Está en tierra.',
        ),
      for (var index = 0; index < 5; index++)
        GamePlayer(
          id: 'green-$index',
          name: 'Verde $index',
          isFake: true,
          team: Team.green,
          position: BoardPosition(name: 'B${index + 1}', column: index + 1, row: 1),
          clue: 'Está en hierba.',
        ),
    ];
    final areas = GameAreaLookup.fromJson(
      quadrants: const {},
      rooms: const {
        'Patio': {'belongBoxes': ['A1', 'A2', 'A3', 'A4', 'A5', 'B1', 'B2', 'B3', 'B4', 'B5']},
      },
    );
    const missions = [
      SecondaryMissionDefinition(id: '1', level: 1, action: 'Acción 1'),
      SecondaryMissionDefinition(id: '2', level: 1, action: 'Acción 2'),
      SecondaryMissionDefinition(id: '3', level: 1, action: 'Acción 3'),
      SecondaryMissionDefinition(id: '4', level: 1, action: 'Acción 4'),
      SecondaryMissionDefinition(id: '5', level: 1, action: 'Acción 5'),
    ];

    final assigned = GameSetup().assignSecondaryMissions(
      players: players.where((player) => player.team == Team.green).toList(),
      targets: players,
      missions: missions,
      areas: areas,
    );

    expect(assigned, hasLength(5));
    expect(assigned.map((mission) => mission['target_participant_id']).toSet(), hasLength(5));
    expect(assigned.every((mission) => (mission['target_participant_id'] as String).startsWith('red-')), isTrue);
    expect(assigned.every((mission) => {'room', 'column', 'row', 'location'}.contains(mission['clue_type'])), isTrue);
  });
}
