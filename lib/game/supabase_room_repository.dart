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

  Future<void> signOut() => _client.auth.signOut();

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

  Future<void> saveAssignments({
    required String roomId,
    required List<GamePlayer> players,
    required GameMystery mystery,
    required List<Map<String, dynamic>> secondaryMissions,
  }) async {
    final assignments = players
        .map((player) => {
              'participant_id': player.id,
              'participant_type': player.isFake ? 'fake' : 'real',
              'character_name': player.characterName,
              'team': player.team!.name,
              // La tabla existente conserva este nombre de columna, pero ahora almacena la familia.
              'role_name': player.familyName ?? 'Sin familia',
              'position_name': player.position!.name,
              'clue': player.clue,
            })
        .toList();
    await _client.rpc('save_game_assignments', params: {
      'p_room_id': roomId,
      'p_assignments': assignments,
      'p_mystery': mystery.toJson(),
    });
    await _client.rpc('save_secondary_missions', params: {
      'p_room_id': roomId,
      'p_missions': secondaryMissions,
    });
  }

  Future<GameMystery?> roomMystery(String roomId) async {
    final rows = await _client
        .from('game_room_mysteries')
        .select('thief_participant_id, accomplice_participant_ids, suspect_room_names')
        .eq('room_id', roomId);
    if ((rows as List<dynamic>).isEmpty) return null;
    final mystery = rows.first as Map<String, dynamic>;
    return GameMystery(
      thiefId: mystery['thief_participant_id'] as String,
      accompliceIds: (mystery['accomplice_participant_ids'] as List<dynamic>).cast<String>(),
      suspectRoomNames: (mystery['suspect_room_names'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Future<List<FamilyBalance>> familyBalances(String roomId) async {
    final rows = await _client
        .from('game_family_balances')
        .select('team, family_name, coins')
        .eq('room_id', roomId)
        .order('team')
        .order('family_name');
    return (rows as List<dynamic>).map((row) {
      final value = row as Map<String, dynamic>;
      return FamilyBalance(
        team: Team.values.byName(value['team'] as String),
        familyName: value['family_name'] as String,
        coins: value['coins'] as int,
      );
    }).toList();
  }

  Future<void> changeFamilyCoins({
    required String roomId,
    required FamilyBalance balance,
    required int amount,
  }) =>
      _client.rpc('change_game_family_coins', params: {
        'p_room_id': roomId,
        'p_team': balance.team.name,
        'p_family_name': balance.familyName,
        'p_amount': amount,
      });

  Future<int?> myFamilyCoins(String roomId) async {
    final assignment = await myAssignment(roomId);
    if (assignment == null) return null;
    final rows = await _client
        .from('game_family_balances')
        .select('coins')
        .eq('room_id', roomId)
        .eq('team', assignment.team!.name)
        .eq('family_name', assignment.familyName ?? 'Sin familia');
    if ((rows as List<dynamic>).isEmpty) return null;
    return (rows.first as Map<String, dynamic>)['coins'] as int;
  }

  Future<PurchaseSettings> purchaseSettings(String roomId) async {
    final rows = await _client
        .from('game_room_purchase_settings')
        .select('clue_enabled, quadrant_enabled, quadrant_locations_enabled')
        .eq('room_id', roomId);
    if ((rows as List<dynamic>).isEmpty) {
      return const PurchaseSettings(clueEnabled: false, quadrantEnabled: false, quadrantLocationsEnabled: false);
    }
    final settings = rows.first as Map<String, dynamic>;
    return PurchaseSettings(
      clueEnabled: settings['clue_enabled'] as bool,
      quadrantEnabled: settings['quadrant_enabled'] as bool,
      quadrantLocationsEnabled: settings['quadrant_locations_enabled'] as bool,
    );
  }

  Future<void> setPurchaseEnabled({required String roomId, required String item, required bool enabled}) =>
      _client.rpc('set_game_purchase_enabled', params: {
        'p_room_id': roomId,
        'p_item': item,
        'p_enabled': enabled,
      });

  Future<String> purchaseGameItem({required String roomId, required String item, String? quadrant}) async {
    if (item == 'clue') {
      final result = await _client.rpc('purchase_team_lost_clue', params: {'p_room_id': roomId});
      return result as String;
    }
    final result = await _client.rpc('purchase_game_item', params: {
      'p_room_id': roomId,
      'p_item': item,
      if (quadrant != null) 'p_quadrant': quadrant,
    });
    return result as String? ?? 'Compra registrada.';
  }

  Future<List<TeamQuadrant>> myTeamQuadrants(String roomId) async {
    final assignment = await myAssignment(roomId);
    if (assignment == null) return const [];
    final rows = await _client
        .from('game_team_quadrants')
        .select('team, quadrant, source')
        .eq('room_id', roomId)
        .eq('team', assignment.team!.name)
        // Incluso si quien juega es el admin, el cuadrante secreto solo se
        // consulta desde la pantalla de administración.
        .neq('source', 'secret')
        .order('quadrant');
    return (rows as List<dynamic>).map((row) {
      final value = row as Map<String, dynamic>;
      return TeamQuadrant(
        team: Team.values.byName(value['team'] as String),
        quadrant: value['quadrant'] as String,
        source: value['source'] as String,
      );
    }).toList();
  }

  Future<List<TeamQuadrant>> roomTeamQuadrants(String roomId) async {
    final rows = await _client
        .from('game_team_quadrants')
        .select('team, quadrant, source')
        .eq('room_id', roomId)
        .order('team')
        .order('quadrant');
    return (rows as List<dynamic>).map((row) {
      final value = row as Map<String, dynamic>;
      return TeamQuadrant(
        team: Team.values.byName(value['team'] as String),
        quadrant: value['quadrant'] as String,
        source: value['source'] as String,
      );
    }).toList();
  }

  Future<List<QuadrantLocation>> myQuadrantLocations(String roomId) async {
    final assignment = await myAssignment(roomId);
    if (assignment == null) return const [];
    final rows = await _client
        .from('game_team_quadrant_locations')
        .select('quadrant, position_name')
        .eq('room_id', roomId)
        .eq('team', assignment.team!.name)
        .order('quadrant')
        .order('position_name');
    return (rows as List<dynamic>).map((row) {
      final value = row as Map<String, dynamic>;
      return QuadrantLocation(
        quadrant: value['quadrant'] as String,
        positionName: value['position_name'] as String,
      );
    }).toList();
  }

  Future<CurrentSecondaryMission?> myCurrentSecondaryMission(String roomId) async {
    final row = await _client.rpc('my_current_secondary_mission', params: {'p_room_id': roomId});
    if (row == null || row is List && row.isEmpty) return null;
    final value = _firstRow(row);
    return CurrentSecondaryMission(
      id: value['mission_id'] as String,
      level: value['mission_level'] as int,
      action: value['mission_action'] as String,
      number: value['mission_number'] as int,
    );
  }

  Future<String> completeSecondaryMission({required String roomId, required String missionId}) async {
    final result = await _client.rpc('complete_secondary_mission', params: {
      'p_room_id': roomId,
      'p_mission_id': missionId.trim(),
    });
    return result as String;
  }

  Future<CompassSecret?> myCompassSecret(String roomId) async {
    final result = await _client.rpc('my_compass_secret', params: {'p_room_id': roomId});
    if (result == null || result is List && result.isEmpty) return null;
    final value = _firstRow(result);
    final role = value['role'] as String?;
    return CompassSecret(
      role: role == null ? null : CompassRole.values.byName(role),
      word: value['secret_word'] as String?,
      canCauseDamage: value['can_cause_damage'] as bool? ?? false,
      pendingDamageCount: value['pending_damage_count'] as int? ?? 0,
      canPayBribes: value['can_pay_bribes'] as bool? ?? false,
    );
  }

  Future<List<SabotageTarget>> sabotageTargets(String roomId) async {
    final rows = await _client.rpc('my_sabotage_targets', params: {'p_room_id': roomId});
    return (rows as List<dynamic>)
        .map((row) {
          final value = row as Map<String, dynamic>;
          return SabotageTarget(
            id: value['participant_id'] as String,
            characterName: value['character_name'] as String,
            pendingDamageCount: value['pending_damage_count'] as int,
          );
        })
        .toList();
  }

  Future<String> causeDamage({required String roomId, required String targetParticipantId}) async =>
      (await _client.rpc('cause_compass_damage', params: {
        'p_room_id': roomId,
        'p_target_participant_id': targetParticipantId,
      })) as String;

  Future<String> payCompassBribes(String roomId) async =>
      (await _client.rpc('pay_compass_bribes', params: {'p_room_id': roomId})) as String;

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
      familyName: assignment['role_name'] as String,
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
    final secondaryRows = await _client
        .from('game_team_secondary_clues')
        .select('clue')
        .eq('room_id', roomId)
        .eq('team', assignment.team!.name);
    return [
      ...(rows as List<dynamic>).map((row) => (row as Map<String, dynamic>)['clue'] as String),
      ...(secondaryRows as List<dynamic>).map((row) => (row as Map<String, dynamic>)['clue'] as String),
    ];
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
        familyName: assignment['role_name'] as String,
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
