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
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
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
          actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
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
                    Text('Rol: ${assignment.roleName}'),
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
  late Future<GameRoom> _room;
  List<GamePlayer>? _assignedPlayers;
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

  Future<void> _assignPositions(List<MapTile> tiles, GameRoom room) async {
    final players = GameSetup().initialize(players: room.players, tiles: tiles);
    setState(() => _assignedPlayers = players);
    try {
      await widget.rooms.saveAssignments(roomId: room.id, players: players);
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
          future: Future.wait<Object>([_tiles, _room]),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final tiles = snapshot.data![0] as List<MapTile>;
            final room = snapshot.data![1] as GameRoom;
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
                  onPressed: () => _assignPositions(tiles, room),
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(_assignedPlayers == null ? 'Asignar casillas' : 'Repartir de nuevo'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Object>>(
                    future: Future.wait<Object>([
                      widget.rooms.roomAssignments(room),
                      widget.rooms.roomClues(room.id),
                    ]),
                    builder: (context, assignmentsSnapshot) {
                      if (assignmentsSnapshot.hasError) return Text(assignmentsSnapshot.error.toString());
                      final storedPlayers = assignmentsSnapshot.hasData
                          ? assignmentsSnapshot.data![0] as List<GamePlayer>
                          : null;
                      final clues = assignmentsSnapshot.hasData
                          ? assignmentsSnapshot.data![1] as Map<String, String>
                          : const <String, String>{};
                      final players = _assignedPlayers ?? storedPlayers;
                      if (players == null || players.isEmpty) {
                        return const Center(child: Text('Solo el admin puede consultar y generar este listado.'));
                      }
                      return ListView.builder(
                        itemCount: players.length,
                        itemBuilder: (context, index) {
                          final player = players[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _teamColor(player.team!),
                              child: Text(player.team!.label.substring(0, 1)),
                            ),
                            title: Text('${player.name} - ${player.characterName}'),
                            subtitle: Text(
                              'Equipo ${player.team!.label} - ${player.roleName}${player.isAdmin ? ' - Admin' : ''}\nPista: ${player.clue ?? clues[player.id] ?? 'Sin pista'}',
                            ),
                            isThreeLine: true,
                            trailing: Text(player.position!.name, style: Theme.of(context).textTheme.titleMedium),
                          );
                        },
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
