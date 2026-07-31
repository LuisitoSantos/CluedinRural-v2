import 'dart:math';

import 'game_models.dart';

/// Sustituible por un repositorio de Supabase sin cambiar las pantallas.
class LocalRoomRepository {
  final Map<String, GameRoom> _roomsByCode = {};
  final Random _random = Random();

  GameRoom createRoom(String playerName) {
    final code = _newCode();
    final admin = GamePlayer(
      id: _newId(),
      name: playerName.trim(),
      isAdmin: true,
    );
    final room = GameRoom(
      id: _newId(),
      code: code,
      adminId: admin.id,
      players: [admin],
    );
    _roomsByCode[code] = room;
    return room;
  }

  GameRoom joinRoom({required String code, required String playerName}) {
    final normalizedCode = code.trim().toUpperCase();
    final room = _roomsByCode[normalizedCode];
    if (room == null) throw StateError('No existe ninguna sala con ese código.');
    if (room.players.any((player) => player.name == playerName.trim())) {
      throw StateError('Ese nombre ya está en uso en la sala.');
    }
    final updated = room.copyWith(players: [
      ...room.players,
      GamePlayer(id: _newId(), name: playerName.trim()),
    ]);
    _roomsByCode[normalizedCode] = updated;
    return updated;
  }

  String _newCode() {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String code;
    do {
      code = List.generate(5, (_) => characters[_random.nextInt(characters.length)]).join();
    } while (_roomsByCode.containsKey(code));
    return code;
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}
