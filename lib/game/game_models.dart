class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.name,
    this.isAdmin = false,
    this.isFake = false,
    this.team,
    this.position,
    this.characterName,
    this.roleName,
    this.clue,
  });

  final String id;
  final String name;
  final bool isAdmin;
  final bool isFake;
  final Team? team;
  final BoardPosition? position;
  final String? characterName;
  final String? roleName;
  final String? clue;

  GamePlayer copyWith({
    Team? team,
    BoardPosition? position,
    String? characterName,
    String? roleName,
    String? clue,
  }) => GamePlayer(
        id: id,
        name: name,
        isAdmin: isAdmin,
        isFake: isFake,
        team: team ?? this.team,
        position: position ?? this.position,
        characterName: characterName ?? this.characterName,
        roleName: roleName ?? this.roleName,
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

enum Team { red, blue, green, yellow }

extension TeamDetails on Team {
  String get label => switch (this) {
        Team.red => 'Rojo',
        Team.blue => 'Azul',
        Team.green => 'Verde',
        Team.yellow => 'Amarillo',
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
