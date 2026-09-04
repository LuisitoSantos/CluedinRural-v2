class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.name,
    this.isAdmin = false,
    this.isFake = false,
    this.team,
    this.position,
    this.characterName,
    this.familyName,
    this.clue,
  });

  final String id;
  final String name;
  final bool isAdmin;
  final bool isFake;
  final Team? team;
  final BoardPosition? position;
  final String? characterName;
  final String? familyName;
  final String? clue;

  GamePlayer copyWith({
    Team? team,
    BoardPosition? position,
    String? characterName,
    String? familyName,
    String? clue,
  }) => GamePlayer(
        id: id,
        name: name,
        isAdmin: isAdmin,
        isFake: isFake,
        team: team ?? this.team,
        position: position ?? this.position,
        characterName: characterName ?? this.characterName,
        familyName: familyName ?? this.familyName,
        clue: clue ?? this.clue,
      );
}

class PlayerAccount {
  const PlayerAccount({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}

class GameRoom {
  const GameRoom({
    required this.id,
    required this.code,
    required this.adminId,
    required this.players,
  });

  final String id;
  final String code;
  final String adminId;
  final List<GamePlayer> players;

  bool isAdmin(String playerId) => adminId == playerId;

  GameRoom copyWith({List<GamePlayer>? players}) => GameRoom(
        id: id,
        code: code,
        adminId: adminId,
        players: players ?? this.players,
      );
}

class GameMystery {
  const GameMystery({
    required this.thiefId,
    required this.accompliceIds,
    this.suspectRoomNames = const [],
  });

  final String thiefId;
  final List<String> accompliceIds;
  /// Una estancia por sospechoso, en el mismo orden que [suspectIds].
  /// No se eliminan los duplicados: tres sospechosos pueden compartir estancia.
  final List<String> suspectRoomNames;

  List<String> get suspectIds => [thiefId, ...accompliceIds];

  Map<String, dynamic> toJson() => {
        'thief_participant_id': thiefId,
        'accomplice_participant_ids': accompliceIds,
        'compass_holder_participant_id': thiefId,
        'suspect_room_names': suspectRoomNames,
      };
}

class FamilyBalance {
  const FamilyBalance({required this.team, required this.familyName, required this.coins});

  final Team team;
  final String familyName;
  final int coins;
}

class PurchaseSettings {
  const PurchaseSettings({
    required this.clueEnabled,
    required this.quadrantEnabled,
    required this.quadrantLocationsEnabled,
  });

  final bool clueEnabled;
  final bool quadrantEnabled;
  final bool quadrantLocationsEnabled;
}

class TeamQuadrant {
  const TeamQuadrant({required this.team, required this.quadrant, required this.source});

  final Team team;
  final String quadrant;
  /// `initial`, `secret` o `purchase`.
  final String source;
}

class QuadrantLocation {
  const QuadrantLocation({required this.quadrant, required this.positionName});

  final String quadrant;
  final String positionName;
}

class SecondaryMissionDefinition {
  const SecondaryMissionDefinition({required this.id, required this.level, required this.action});

  final String id;
  final int level;
  final String action;

  factory SecondaryMissionDefinition.fromJson(String id, Map<String, dynamic> json) => SecondaryMissionDefinition(
        id: id,
        level: json['Nivel'] as int,
        action: json['Accion'] as String,
      );
}

class CurrentSecondaryMission {
  const CurrentSecondaryMission({required this.id, required this.level, required this.action, required this.number});

  final String id;
  final int level;
  final String action;
  final int number;
}

enum CompassRole { thief, accomplice }

extension CompassRoleDetails on CompassRole {
  String get label => switch (this) {
        CompassRole.thief => 'Eres el ladron y llevas el Compas Dorado.',
        CompassRole.accomplice => 'Eres complice del robo del Compas Dorado.',
      };
}

class GameAreaLookup {
  const GameAreaLookup({required this._quadrantsByBox, required this._roomsByBox});

  final Map<String, String> _quadrantsByBox;
  final Map<String, List<String>> _roomsByBox;

  factory GameAreaLookup.fromJson({
    required Map<String, dynamic> quadrants,
    required Map<String, dynamic> rooms,
  }) {
    final quadrantsByBox = <String, String>{};
    final roomsByBox = <String, List<String>>{};
    for (final entry in quadrants.entries) {
      for (final box in _boxesFromArea(entry.value as Map<String, dynamic>)) {
        quadrantsByBox[box] = entry.key;
      }
    }
    for (final entry in rooms.entries) {
      for (final box in _boxesFromArea(entry.value as Map<String, dynamic>)) {
        roomsByBox.putIfAbsent(box, () => []).add(entry.key);
      }
    }
    return GameAreaLookup(quadrantsByBox: quadrantsByBox, roomsByBox: roomsByBox);
  }

  String? quadrantFor(String box) => _quadrantsByBox[box];

  List<String> roomsFor(String box) => _roomsByBox[box] ?? const [];

  static Iterable<String> _boxesFromArea(Map<String, dynamic> area) sync* {
    for (final group in area['belongBoxes'] as List<dynamic>) {
      yield* (group as List<dynamic>).cast<String>();
    }
  }
}

enum Team { red, blue, green, yellow }

extension TeamDetails on Team {
  String get label => switch (this) {
        Team.red => 'Rojo',
        Team.blue => 'Azul',
        Team.green => 'Verde',
        Team.yellow => 'Amarillo',
  };

  String get familyName => switch (this) {
        Team.red => 'Rossi',
        Team.blue => 'Beaumont',
        Team.green => "O'Doherty",
        Team.yellow => 'Romanov',
      };
}

class BoardPosition {
  const BoardPosition({
    required this.name,
    required this.column,
    required this.row,
  });

  final String name;
  final int column;
  final int row;
}

class MapTile extends BoardPosition {
  const MapTile({
    required super.name,
    required super.column,
    required super.row,
    required this.type,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  final String type;
  final String up;
  final String down;
  final String left;
  final String right;

  factory MapTile.fromJson(Map<String, dynamic> json) {
    final coordinates = (json['coordinates'] as List<dynamic>).first as List<dynamic>;
    return MapTile(
      name: json['name'] as String,
      type: json['type'] as String? ?? '',
      up: json['up'] as String? ?? '',
      down: json['down'] as String? ?? '',
      left: json['left'] as String? ?? '',
      right: json['right'] as String? ?? '',
      column: coordinates[0] as int,
      row: coordinates[1] as int,
    );
  }
}
