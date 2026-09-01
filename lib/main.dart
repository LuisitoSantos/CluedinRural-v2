import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'game/game_models.dart';
import 'game/game_setup.dart';
import 'game/supabase_room_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    runApp(const _MissingConfigurationApp());
    return;
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
      //persistSession: true,
    ),
  );
  runApp(const RuralMurdokuApp());
}

class _MissingConfigurationApp extends StatelessWidget {
  const _MissingConfigurationApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(body: Center(child: Text('Falta configurar Supabase.'))),
      );
}

class RuralMurdokuApp extends StatelessWidget {
  const RuralMurdokuApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Rural Murdoku',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: _SessionGate(rooms: SupabaseRoomRepository(Supabase.instance.client)),
      );
}

class _SessionGate extends StatelessWidget {
  const _SessionGate({required this.rooms});
  final SupabaseRoomRepository rooms;

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayerAccount?>(
        future: rooms.currentAccount(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == null
              ? AccessPage(rooms: rooms)
              : MyRoomsPage(rooms: rooms, account: snapshot.data!);
        },
      );
}

class AccessPage extends StatefulWidget {
  const AccessPage({super.key, required this.rooms});
  final SupabaseRoomRepository rooms;

  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_name.text.trim().isEmpty || !RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) {
      return _showError('Escribe un nombre y un PIN de 4 a 6 cifras.');
    }
    setState(() => _loading = true);
    try {
      final account = await widget.rooms.authenticate(name: _name.text, pin: _pin.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MyRoomsPage(rooms: widget.rooms, account: account),
      ));
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rural Murdoku')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Identificate', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre de jugador')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'PIN (4 a 6 cifras)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loading ? null : _continue,
                    child: Text(_loading ? 'Entrando...' : 'Continuar'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'La primera vez se crea tu perfil. Conserva el PIN: lo necesitaras si reinstalas la app.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class MyRoomsPage extends StatefulWidget {
  const MyRoomsPage({super.key, required this.rooms, required this.account});
  final SupabaseRoomRepository rooms;
  final PlayerAccount account;

  @override
  State<MyRoomsPage> createState() => _MyRoomsPageState();
}

class _MyRoomsPageState extends State<MyRoomsPage> {
  late Future<List<GameRoom>> _rooms = widget.rooms.myRooms();

  void _reload() => setState(() => _rooms = widget.rooms.myRooms());

  Future<void> _signOut() async {
    try {
      await widget.rooms.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AccessPage(rooms: widget.rooms)),
        (_) => false,
      );
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _createRoom() async {
    try {
      final room = await widget.rooms.createRoom(widget.account.displayName);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RoomPage(room: room, account: widget.account, rooms: widget.rooms),
      ));
      _reload();
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _joinRoom() async {
    final code = await _askForCode();
    if (code == null) return;
    try {
      final room = await widget.rooms.joinRoom(code: code, playerName: widget.account.displayName);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RoomPage(room: room, account: widget.account, rooms: widget.rooms),
      ));
      _reload();
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<String?> _askForCode() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unirme a una sala'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Codigo de sala'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unirme')),
        ],
      ),
    );
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('Mis salas - ${widget.account.displayName}'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Cerrar sesion',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: FutureBuilder<List<GameRoom>>(
          future: _rooms,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final rooms = snapshot.data!;
            if (rooms.isEmpty) return const Center(child: Text('Aun no estas en ninguna sala.'));
            return ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return ListTile(
                  title: Text('Sala ${room.code}'),
                  subtitle: Text('${room.players.length} jugadores'),
                  trailing: room.isAdmin(widget.account.userId) ? const Icon(Icons.admin_panel_settings_outlined) : null,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RoomPage(room: room, account: widget.account, rooms: widget.rooms),
                  )),
                );
              },
            );
          },
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _joinRoom, child: const Text('Unirme con codigo'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _createRoom, child: const Text('Crear sala'))),
            ],
          ),
        ),
      );
}

class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.room, required this.account, required this.rooms});
  final GameRoom room;
  final PlayerAccount account;
  final SupabaseRoomRepository rooms;

  @override
  Widget build(BuildContext context) {
    final isAdmin = room.isAdmin(account.userId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sala'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => RoomPage(room: room, account: account, rooms: rooms),
            )),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Codigo de sala', style: Theme.of(context).textTheme.titleMedium),
          SelectableText(room.code, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          const Text('Comparte este codigo con el resto de jugadores.'),
          const SizedBox(height: 28),
          Text('Has entrado como ${account.displayName}${isAdmin ? ' (admin)' : ''}.'),
          const SizedBox(height: 12),
          Text('Jugadores en la sala: ${room.players.length}'),
          const SizedBox(height: 20),
          FutureBuilder<GamePlayer?>(
            future: rooms.myAssignment(room.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('No se pudo cargar tu ficha: ${snapshot.error}');
              final assignment = snapshot.data;
              if (assignment == null) return const Text('Esperando a que el admin inicie la partida.');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(assignment.characterName!, style: Theme.of(context).textTheme.headlineSmall),
                    Text('Equipo ${assignment.team!.label}'),
                    Text('Familia: ${assignment.familyName}'),
                    Text('Casilla: ${assignment.position!.name}'),
                  ]),
                ),
              );
            },
          ),
          FutureBuilder<List<String>>(
            future: rooms.myTeamClues(room.id),
            builder: (context, snapshot) {
              final clues = snapshot.data ?? const <String>[];
              if (clues.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pistas de tu equipo', style: Theme.of(context).textTheme.titleMedium),
                  ...clues.map((clue) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('• $clue'),
                      )),
                ]),
              );
            },
          ),
          FutureBuilder<CompassRole?>(
            future: rooms.myCompassRole(room.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const SizedBox.shrink();
              final role = snapshot.data;
              if (role == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(role.label, style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          if (isAdmin)
            FilledButton.icon(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Administrar partida'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdminPage(room: room, rooms: rooms),
              )),
            )
          else
            const Text('Espera a que el admin inicie la partida.', textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.room, required this.rooms});
  final GameRoom room;
  final SupabaseRoomRepository rooms;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final Future<List<MapTile>> _tiles = _loadTiles();
  late final Future<Map<String, CharacterProfile>> _characters = _loadCharacters();
  late final Future<GameAreaLookup> _areas = _loadAreas();
  late Future<GameRoom> _room;
  List<GamePlayer>? _assignedPlayers;
  GameMystery? _mystery;
  int _fakePlayerCount = 20;

  @override
  void initState() {
    super.initState();
    _room = widget.rooms.getRoom(widget.room.id);
  }

  Future<List<MapTile>> _loadTiles() async {
    final source = await rootBundle.loadString('lib/resources/mapa.json');
    final map = jsonDecode(source) as Map<String, dynamic>;
    return map.values.map((value) => MapTile.fromJson(value as Map<String, dynamic>)).toList();
  }

  Future<Map<String, CharacterProfile>> _loadCharacters() async {
    final source = await rootBundle.loadString('lib/resources/personajes');
    final data = jsonDecode(source) as Map<String, dynamic>;
    return {
      for (final entry in data.entries)
        entry.key: CharacterProfile.fromJson(entry.key, entry.value as Map<String, dynamic>),
    };
  }

  Future<GameAreaLookup> _loadAreas() async {
    final sources = await Future.wait([
      rootBundle.loadString('lib/resources/cuadrantes.json'),
      rootBundle.loadString('lib/resources/estancias.json'),
    ]);
    return GameAreaLookup.fromJson(
      quadrants: jsonDecode(sources[0]) as Map<String, dynamic>,
      rooms: jsonDecode(sources[1]) as Map<String, dynamic>,
    );
  }

  Future<void> _assignPositions(
    List<MapTile> tiles,
    GameRoom room,
    Map<String, CharacterProfile> characters,
  ) async {
    try {
      final setup = GameSetup();
      final players = setup.initialize(
        players: room.players,
        tiles: tiles,
        charactersByName: characters,
      );
      final mystery = setup.selectMystery(players);
      await widget.rooms.saveAssignments(roomId: room.id, players: players, mystery: mystery);
      if (!mounted) return;
      setState(() {
        _assignedPlayers = players;
        _mystery = mystery;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida iniciada.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addFakePlayers() async {
    try {
      await widget.rooms.addFakePlayers(roomId: widget.room.id, count: _fakePlayerCount);
      if (!mounted) return;
      setState(() {
        _assignedPlayers = null;
        _room = widget.rooms.getRoom(widget.room.id);
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Administracion de partida')),
        body: FutureBuilder<List<Object>>(
          future: Future.wait<Object>([_tiles, _characters, _areas, _room]),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final tiles = snapshot.data![0] as List<MapTile>;
            final characters = snapshot.data![1] as Map<String, CharacterProfile>;
            final areas = snapshot.data![2] as GameAreaLookup;
            final room = snapshot.data![3] as GameRoom;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Text('Ficticios:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _fakePlayerCount,
                    items: List.generate(11, (index) => index + 20)
                        .map((count) => DropdownMenuItem(value: count, child: Text('$count')))
                        .toList(),
                    onChanged: (count) => setState(() => _fakePlayerCount = count!),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: _addFakePlayers, child: const Text('Añadir')),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _assignPositions(tiles, room, characters),
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(_assignedPlayers == null ? 'Asignar casillas' : 'Repartir de nuevo'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Object?>>(
                    future: Future.wait<Object?>([
                      widget.rooms.roomAssignments(room),
                      widget.rooms.roomClues(room.id),
                      widget.rooms.roomMystery(room.id),
                    ]),
                    builder: (context, assignmentsSnapshot) {
                      if (assignmentsSnapshot.hasError) return Text(assignmentsSnapshot.error.toString());
                      final storedPlayers = assignmentsSnapshot.hasData
                          ? assignmentsSnapshot.data![0] as List<GamePlayer>
                          : null;
                      final clues = assignmentsSnapshot.hasData
                          ? assignmentsSnapshot.data![1] as Map<String, String>
                          : const <String, String>{};
                      final storedMystery = assignmentsSnapshot.hasData
                          ? assignmentsSnapshot.data![2] as GameMystery?
                          : null;
                      final players = _assignedPlayers ?? storedPlayers;
                      final mystery = _mystery ?? storedMystery;
                      if (players == null || players.isEmpty) {
                        return const Center(child: Text('Solo el admin puede consultar y generar este listado.'));
                      }
                      return ListView(
                        children: [
                          if (mystery != null) _MysteryCard(mystery: mystery, players: players, areas: areas),
                          ...players.map((player) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _teamColor(player.team!),
                                  child: Text(player.team!.label.substring(0, 1)),
                                ),
                                title: Text('${player.name} - ${player.characterName}'),
                                subtitle: Text(
                                  'Equipo ${player.team!.label}${player.familyName == null ? '' : ' - Familia ${player.familyName}'}${player.isAdmin ? ' - Admin' : ''}\nPista: ${player.clue ?? clues[player.id] ?? 'Sin pista'}',
                                ),
                                isThreeLine: true,
                                trailing: Text(player.position!.name, style: Theme.of(context).textTheme.titleMedium),
                              )),
                        ],
                      );
                    },
                  ),
                ),
              ]),
            );
          },
        ),
      );
}

class _MysteryCard extends StatelessWidget {
  const _MysteryCard({required this.mystery, required this.players, required this.areas});

  final GameMystery mystery;
  final List<GamePlayer> players;
  final GameAreaLookup areas;

  @override
  Widget build(BuildContext context) {
    final playersById = {for (final player in players) player.id: player};
    final thief = playersById[mystery.thiefId];
    final accomplices = mystery.accompliceIds
    .map((id) => playersById[id])
    .whereType<GamePlayer>()
    .toList();
    if (thief == null || accomplices.length != 2) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Secreto: el Compas Dorado', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _villainLocation('Ladron (lleva el compas)', thief),
            _villainLocation('Complice 1', accomplices[0]),
            _villainLocation('Complice 2', accomplices[1]),
          ],
        ),
      ),
    );
  }

  Widget _villainLocation(String role, GamePlayer player) {
    final position = player.position!;
    final quadrant = areas.quadrantFor(position.name) ?? 'sin cuadrante';
    final rooms = areas.roomsFor(position.name);
    final roomLabel = rooms.isEmpty ? 'sin estancia' : rooms.join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$role: ${player.name} — casilla ${position.name}, cuadrante $quadrant, estancia $roomLabel.'),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message))));
}

Color _teamColor(Team team) => switch (team) {
      Team.red => Colors.red,
      Team.blue => Colors.blue,
      Team.green => Colors.green,
      Team.yellow => Colors.amber.shade800,
    };
