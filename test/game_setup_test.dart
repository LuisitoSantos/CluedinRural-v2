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
    expect(result.every((player) => player.familyName == null), isTrue);
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
}
