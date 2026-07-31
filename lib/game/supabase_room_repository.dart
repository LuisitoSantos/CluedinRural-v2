import 'package:supabase_flutter/supabase_flutter.dart';

import 'game_models.dart';

class SupabaseRoomRepository {
  SupabaseRoomRepository(this._client);

  final SupabaseClient _client;

  Future<PlayerAccount?> currentAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final rows = await _client
        .from('game_player_accounts')
        .select('auth_user_id, display_name')
        .eq('auth_user_id', user.id);
    if ((rows as List<dynamic>).isEmpty) return null;
    final account = rows.first as Map<String, dynamic>;
    return PlayerAccount(
      userId: account['auth_user_id'] as String,
      displayName: account['display_name'] as String,
    );
  }

  Future<PlayerAccount> authenticate({required String name, required String pin}) async {
    await _ensureAnonymousUser();
    final data = await _client.rpc('authenticate_game_player', params: {
      'p_display_name': name.trim(),
      'p_pin': pin,
    });
    final account = _firstRow(data);
    return PlayerAccount(
      userId: account['auth_user_id'] as String,
      displayName: account['display_name'] as String,
    );
  }

  Future<List<GameRoom>> myRooms() async {
    final userId = await _ensureAnonymousUser();
    final rows = await _client
        .from('game_room_players')
        .select('room_id')
        .eq('user_id', userId)
        .order('joined_at', ascending: false);
    return Future.wait((rows as List<dynamic>)
        .map((row) => getRoom((row as Map<String, dynamic>)['room_id'] as String)));
  }

  Future<GameRoom> createRoom(String playerName) async {
    await _ensureAnonymousUser();
    final data = await _client.rpc('create_game_room', params: {'p_display_name': playerName.trim()});
    return getRoom(_firstRow(data)['room_id'] as String);
  }

  Future<GameRoom> joinRoom({required String code, required String playerName}) async {
    await _ensureAnonymousUser();
    final data = await _client.rpc('join_game_room', params: {
      'p_code': code.trim().toUpperCase(),
      'p_display_name': playerName.trim(),
    });
    return getRoom(_firstRow(data)['room_id'] as String);
  }

  Future<GameRoom> getRoom(String roomId) async {
    final room = await _client
        .from('game_rooms')
        .select('id, code, admin_user_id')
        .eq('id', roomId)
        .single();
    final members = await _client
        .from('game_room_players')
        .select('user_id, display_name')
        .eq('room_id', roomId)
        .order('joined_at');
    final fakePlayers = await _client
        .from('game_room_fake_players')
        .select('id, display_name')
        .eq('room_id', roomId)
        .order('created_at');
    final adminId = room['admin_user_id'] as String;
    return GameRoom(
      id: room['id'] as String,
      code: room['code'] as String,
      adminId: adminId,
      players: [
        ...(members as List<dynamic>).map((member) => GamePlayer(
                id: member['user_id'] as String,
                name: member['display_name'] as String,
                isAdmin: member['user_id'] == adminId,
              )),
        ...(fakePlayers as List<dynamic>).map((player) => GamePlayer(
              id: player['id'] as String,
              name: player['display_name'] as String,
              isFake: true,
            )),
      ],
    );
  }

  Future<void> addFakePlayers({required String roomId, required int count}) =>
      _client.rpc('add_game_fake_players', params: {'p_room_id': roomId, 'p_count': count});

  Future<void> saveAssignments({required String roomId, required List<GamePlayer> players}) {
    final assignments = players
        .map((player) => {
              'participant_id': player.id,
              'participant_type': player.isFake ? 'fake' : 'real',
              'character_name': player.characterName,
              'team': player.team!.name,
              'role_name': player.roleName,
              'position_name': player.position!.name,
              'clue': player.clue,
            })
        .toList();
    return _client.rpc('save_game_assignments', params: {
      'p_room_id': roomId,
      'p_assignments': assignments,
    });
  }

  Future<GamePlayer?> myAssignment(String roomId) async {
    final userId = await _ensureAnonymousUser();
    final rows = await _client
        .from('game_assignments')
        .select('character_name, team, role_name, position_name')
        .eq('room_id', roomId)
        .eq('user_id', userId);
    if ((rows as List<dynamic>).isEmpty) return null;
    final assignment = rows.first as Map<String, dynamic>;
    return GamePlayer(
      id: userId,
      name: '',
      characterName: assignment['character_name'] as String,
      roleName: assignment['role_name'] as String,
      team: Team.values.byName(assignment['team'] as String),
      position: BoardPosition(name: assignment['position_name'] as String, column: 0, row: 0),
    );
  }

  Future<List<String>> myTeamClues(String roomId) async {
    final userId = await _ensureAnonymousUser();
    final assignment = await myAssignment(roomId);
    if (assignment == null) return const [];
    final rows = await _client
        .from('game_team_clues')
        .select('clue')
        .eq('room_id', roomId)
        .eq('team', assignment.team!.name)
        .neq('target_participant_id', userId);
    return (rows as List<dynamic>).map((row) => (row as Map<String, dynamic>)['clue'] as String).toList();
  }

  Future<Map<String, String>> roomClues(String roomId) async {
    final rows = await _client
        .from('game_team_clues')
        .select('target_participant_id, clue')
        .eq('room_id', roomId);
    return {
      for (final row in rows as List<dynamic>)
        (row as Map<String, dynamic>)['target_participant_id'] as String: row['clue'] as String,
    };
  }

  Future<List<GamePlayer>> roomAssignments(GameRoom room) async {
    final rows = await _client
        .from('game_assignments')
        .select('participant_id, participant_type, character_name, team, role_name, position_name')
        .eq('room_id', room.id)
        .order('assigned_at');
    final participants = {for (final player in room.players) player.id: player};
    return (rows as List<dynamic>).map((row) {
      final assignment = row as Map<String, dynamic>;
      final participantId = assignment['participant_id'] as String;
      final participant = participants[participantId];
      return GamePlayer(
        id: participantId,
        name: participant?.name ?? 'Jugador eliminado',
        isAdmin: participant?.isAdmin ?? false,
        isFake: assignment['participant_type'] == 'fake',
        characterName: assignment['character_name'] as String,
        roleName: assignment['role_name'] as String,
        team: Team.values.byName(assignment['team'] as String),
        position: BoardPosition(name: assignment['position_name'] as String, column: 0, row: 0),
      );
    }).toList();
  }

  Future<String> _ensureAnonymousUser() async {
    var user = _client.auth.currentUser;
    if (user == null) {
      final response = await _client.auth.signInAnonymously();
      user = response.user;
    }
    if (user == null) throw StateError('No se pudo crear la sesion de jugador.');
    return user.id;
  }

  Map<String, dynamic> _firstRow(dynamic value) {
    if (value is List && value.isNotEmpty) return value.first as Map<String, dynamic>;
    if (value is Map<String, dynamic>) return value;
    throw StateError('La sala no se pudo crear o encontrar.');
  }
}
