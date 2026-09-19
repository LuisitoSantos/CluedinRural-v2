import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'game/game_models.dart';
import 'game/game_setup.dart';
import 'game/supabase_room_repository.dart';
import 'notifications/push_notifications.dart';

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
  late final Future<List<String>> _characterNames = _loadCharacterNames();
  bool _loading = false;

  Future<List<String>> _loadCharacterNames() async {
    final source = await rootBundle.loadString('lib/resources/personajes.json');
    return (jsonDecode(source) as Map<String, dynamic>).keys.toList()..sort();
  }

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
    // Se inicia directamente desde el toque del usuario: los navegadores
    // solo permiten mostrar el permiso de notificaciones desde esa acción.
    final pushSubscription = PushNotifications.subscribe();
    try {
      final account = await widget.rooms.authenticate(name: _name.text, pin: _pin.text);
      // Nunca se espera a la suscripción para acceder. En algunos móviles el
      // service worker puede tardar; la suscripción continúa en segundo plano.
      unawaited(_savePushSubscription(pushSubscription));
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

  Future<void> _savePushSubscription(Future<PushSubscriptionData> pendingSubscription) async {
    try {
      final subscription = await pendingSubscription;
      if (subscription.supported &&
          subscription.endpoint != null &&
          subscription.p256dh != null &&
          subscription.auth != null) {
        await widget.rooms.savePushSubscription(
          endpoint: subscription.endpoint!,
          p256dh: subscription.p256dh!,
          auth: subscription.auth!,
        );
      }
    } catch (_) {
      // No impedir el acceso al juego si el navegador no admite push o si el
      // jugador decide no conceder permiso.
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
                  FutureBuilder<List<String>>(
                    future: _characterNames,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return const Text('No se pudo cargar la lista de personajes.');
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      return DropdownButtonFormField<String>(
                        value: _name.text.isEmpty ? null : _name.text,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Personaje'),
                        hint: const Text('Elige tu personaje'),
                        items: snapshot.data!
                            .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                            .toList(),
                        onChanged: _loading ? null : (name) => setState(() => _name.text = name ?? ''),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'PIN (4 a 6 cifras)'),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<String>>(
                    future: _characterNames,
                    builder: (context, snapshot) => FilledButton(
                      onPressed: _loading || !snapshot.hasData ? null : _continue,
                      child: Text(_loading ? 'Entrando...' : 'Continuar'),
                    ),
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

  void _reload() => setState(() {
        _rooms = widget.rooms.myRooms();
      });

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
                  title: Text(room.isAdmin(widget.account.userId) ? 'Sala ${room.code}' : 'Sala'),
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

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.room, required this.account, required this.rooms});
  final GameRoom room;
  final PlayerAccount account;
  final SupabaseRoomRepository rooms;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final ValueNotifier<int> _gameRevision = ValueNotifier(0);

  @override
  void dispose() {
    _gameRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final account = widget.account;
    final rooms = widget.rooms;
    final isAdmin = room.isAdmin(account.userId);
    final playerCount = room.players.where((player) => !player.isFake).length;
    return Scaffold(
      appBar: AppBar(
        title: isAdmin
            ? Text('Código: ${room.code} · $playerCount jugadores', style: Theme.of(context).textTheme.labelSmall)
            : const Text('Sala'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final refreshedRoom = await rooms.getRoom(room.id);
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => RoomPage(room: refreshedRoom, account: account, rooms: rooms),
              ));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PlayerGamePanel(room: room, rooms: rooms, gameRevision: _gameRevision),
          const SizedBox(height: 28),
          if (isAdmin)
            FilledButton.icon(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Administrar partida'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdminPage(room: room, rooms: rooms),
              )),
            ),
        ]),
      ),
      bottomNavigationBar: _GameActionsBar(
        room: room,
        rooms: rooms,
        gameRevision: _gameRevision,
      ),
    );
  }
}

class _PlayerGameData {
  const _PlayerGameData({
    required this.assignment,
    required this.coins,
    required this.purchaseSettings,
    required this.clues,
    required this.notices,
    required this.quadrants,
    required this.locations,
    required this.currentMission,
    required this.secret,
  });

  final GamePlayer? assignment;
  final int? coins;
  final PurchaseSettings purchaseSettings;
  final List<TeamClue> clues;
  final List<String> notices;
  final List<TeamQuadrant> quadrants;
  final List<QuadrantLocation> locations;
  final CurrentSecondaryMission? currentMission;
  final CompassSecret? secret;
}

class _PlayerGamePanel extends StatefulWidget {
  const _PlayerGamePanel({required this.room, required this.rooms, required this.gameRevision});

  final GameRoom room;
  final SupabaseRoomRepository rooms;
  final ValueNotifier<int> gameRevision;

  @override
  State<_PlayerGamePanel> createState() => _PlayerGamePanelState();
}

class _PlayerGamePanelState extends State<_PlayerGamePanel> {
  late Future<_PlayerGameData> _gameData;

  @override
  void initState() {
    super.initState();
    _gameData = _loadGameData();
    widget.gameRevision.addListener(_reload);
  }

  @override
  void dispose() {
    widget.gameRevision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
        _gameData = _loadGameData();
      });

  Future<_PlayerGameData> _loadGameData() async {
    final assignment = await widget.rooms.myAssignment(widget.room.id);
    if (assignment == null) {
      return const _PlayerGameData(
        assignment: null,
        coins: null,
        purchaseSettings: PurchaseSettings(clueEnabled: false, quadrantEnabled: false, quadrantLocationsEnabled: false),
        clues: [],
        notices: [],
        quadrants: [],
        locations: [],
        currentMission: null,
        secret: null,
      );
    }
    final results = await Future.wait<Object?>([
      widget.rooms.myFamilyCoins(widget.room.id),
      widget.rooms.purchaseSettings(widget.room.id),
      widget.rooms.myTeamClues(widget.room.id),
      widget.rooms.myGameNotices(widget.room.id),
      widget.rooms.myTeamQuadrants(widget.room.id),
      widget.rooms.myQuadrantLocations(widget.room.id),
      widget.rooms.myCurrentSecondaryMission(widget.room.id),
      widget.rooms.myCompassSecret(widget.room.id),
    ]);
    return _PlayerGameData(
      assignment: assignment,
      coins: results[0] as int?,
      purchaseSettings: results[1] as PurchaseSettings,
      clues: results[2] as List<TeamClue>,
      notices: results[3] as List<String>,
      quadrants: results[4] as List<TeamQuadrant>,
      locations: results[5] as List<QuadrantLocation>,
      currentMission: results[6] as CurrentSecondaryMission?,
      secret: results[7] as CompassSecret?,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PlayerGameData>(
        future: _gameData,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('No se pudo cargar tu ficha: ${snapshot.error}');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final assignment = data.assignment;
          if (assignment == null) return const Text('Esperando a que el admin inicie la partida.');
          final quadrantNames = data.quadrants.map((item) => item.quadrant).toSet().toList()..sort();
          final initialClues = data.clues.where((clue) => clue.kind == TeamClueKind.initial).toList();
          final earnedClues = data.clues.where((clue) => clue.kind != TeamClueKind.initial).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(assignment.characterName!, style: Theme.of(context).textTheme.titleMedium),
                  Text('Equipo: ${assignment.team!.label} · ${assignment.familyName}', style: Theme.of(context).textTheme.bodySmall),
                  Text('Monedas del equipo: ${data.coins ?? 0}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  _SecretRolePanel(secret: data.secret, onCauseDamage: _causeDamage, onPayBribes: _payBribes),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Text('Pistas del equipo', style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Cuadrantes de tu equipo: ${quadrantNames.join(', ')}'),
            ),
            if (data.clues.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aún no hay pistas disponibles.'))
            else ...[
              ...initialClues.map(_clueLine),
              if (initialClues.isNotEmpty && earnedClues.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
              ...earnedClues.map(_clueLine),
            ],
            if (data.notices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Avisos de partida', style: Theme.of(context).textTheme.titleSmall),
              ...data.notices.map((notice) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('⚠ $notice'),
                  )),
            ],
            if (data.locations.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._locationGroups(data.locations).entries.expand((entry) => [
                    Text('Ubicaciones del cuadrante ${entry.key}', style: Theme.of(context).textTheme.titleSmall),
                    ...entry.value.map(
                      (location) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${location.positionName} · ${location.characterName}'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ]),
            ],
            if (data.currentMission != null) ...[
              const SizedBox(height: 20),
              Text('Misión secundaria ${data.currentMission!.number}/${data.currentMission!.total}', style: Theme.of(context).textTheme.titleMedium),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(data.currentMission!.action)),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('ID: ${data.currentMission!.id}')),
            ],
          ]);
        },
      );

  Widget _clueLine(TeamClue clue) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('• ${clue.text}', style: clue.kind == TeamClueKind.lost ? TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600) : null),
      );

  Map<String, List<QuadrantLocation>> _locationGroups(List<QuadrantLocation> locations) {
    final groups = <String, List<QuadrantLocation>>{};
    for (final location in locations) {
      groups.putIfAbsent(location.quadrant, () => []).add(location);
    }
    return groups;
  }

  Future<void> _causeDamage() async {
    try {
      final targets = await widget.rooms.sabotageTargets(widget.room.id);
      if (!mounted || targets.isEmpty) return;
      final target = await showDialog<SabotageTarget>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('¿A quién causar daños?'),
          children: targets
              .map((target) => SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(target),
                    child: Text('${target.characterName}${target.pendingDamageCount == 0 ? '' : ' · ${target.pendingDamageCount} daño(s) pendiente(s)'}'),
                  ))
              .toList(),
        ),
      );
      if (target == null || !mounted) return;
      final result = await widget.rooms.causeDamage(roomId: widget.room.id, targetParticipantId: target.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      widget.gameRevision.value++;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _payBribes() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Pagar sobornos?'),
          content: const Text('Se restarán hasta 30 monedas a todos los equipos. Esta acción solo puede hacerse una vez.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Pagar')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await widget.rooms.payCompassBribes(widget.room.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      widget.gameRevision.value++;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

}

class _SecretRolePanel extends StatefulWidget {
  const _SecretRolePanel({required this.secret, required this.onCauseDamage, required this.onPayBribes});

  final CompassSecret? secret;
  final Future<void> Function() onCauseDamage;
  final Future<void> Function() onPayBribes;

  @override
  State<_SecretRolePanel> createState() => _SecretRolePanelState();
}

class _SecretRolePanelState extends State<_SecretRolePanel> {
  var _visible = false;

  @override
  Widget build(BuildContext context) {
    final role = widget.secret?.role;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton.icon(
        onPressed: () => setState(() => _visible = !_visible),
        icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
        label: Text(_visible ? 'Ocultar información secreta' : 'Ver información secreta'),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
      ),
      if (_visible)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: role == null ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(role?.label ?? 'No tienes un rol secreto en esta partida.'),
            if (role != null) ...[
              const SizedBox(height: 6),
              Text('Palabra para reconoceros: ${widget.secret!.word}', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              Text('Posiciones del grupo', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...widget.secret!.members.map(
                (member) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    member.isSelf
                        ? 'Tu casilla: ${member.positionName}'
                        : 'Aliado: equipo ${member.team.label} · casilla ${member.positionName}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.secret!.canCauseDamage ? widget.onCauseDamage : null,
                icon: const Icon(Icons.lock_outline),
                label: Text(widget.secret!.canCauseDamage ? 'Hacer daño' : 'Daños ya usados o compras desactivadas'),
              ),
              if (role == CompassRole.thief) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: widget.secret!.canPayBribes ? widget.onPayBribes : null,
                  icon: const Icon(Icons.paid_outlined),
                  label: Text(widget.secret!.canPayBribes ? 'Pago de sobornos (−30 a cada equipo)' : 'Sobornos ya pagados'),
                ),
              ],
            ],
          ]),
        ),
    ]);
  }
}

class _GameActionsData {
  const _GameActionsData({required this.assignment, required this.settings, required this.quadrants, required this.currentMission});

  final GamePlayer? assignment;
  final PurchaseSettings settings;
  final List<TeamQuadrant> quadrants;
  final CurrentSecondaryMission? currentMission;
}

class _GameActionsBar extends StatefulWidget {
  const _GameActionsBar({required this.room, required this.rooms, required this.gameRevision});

  final GameRoom room;
  final SupabaseRoomRepository rooms;
  final ValueNotifier<int> gameRevision;

  @override
  State<_GameActionsBar> createState() => _GameActionsBarState();
}

class _GameActionsBarState extends State<_GameActionsBar> {
  late Future<_GameActionsData> _data;
  String? _buyingItem;

  @override
  void initState() {
    super.initState();
    _data = _load();
    widget.gameRevision.addListener(_reload);
  }

  @override
  void dispose() {
    widget.gameRevision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
        _data = _load();
      });

  Future<_GameActionsData> _load() async {
    final assignment = await widget.rooms.myAssignment(widget.room.id);
    if (assignment == null) {
      return const _GameActionsData(
        assignment: null,
        settings: PurchaseSettings(clueEnabled: false, quadrantEnabled: false, quadrantLocationsEnabled: false),
        quadrants: [],
        currentMission: null,
      );
    }
    final results = await Future.wait<Object?>([
      widget.rooms.purchaseSettings(widget.room.id),
      widget.rooms.myTeamQuadrants(widget.room.id),
      widget.rooms.myCurrentSecondaryMission(widget.room.id),
    ]);
    return _GameActionsData(
      assignment: assignment,
      settings: results[0] as PurchaseSettings,
      quadrants: results[1] as List<TeamQuadrant>,
      currentMission: results[2] as CurrentSecondaryMission?,
    );
  }

  Future<void> _purchase(String item, {String? quadrant}) async {
    setState(() => _buyingItem = item);
    try {
      final result = await widget.rooms.purchaseGameItem(roomId: widget.room.id, item: item, quadrant: quadrant);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      widget.gameRevision.value++;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _buyingItem = null);
    }
  }

  Future<void> _buyLocations(List<TeamQuadrant> quadrants) async {
    final choices = quadrants.map((item) => item.quadrant).toSet().toList()..sort();
    if (choices.isEmpty) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿De qué cuadrante quieres las ubicaciones?'),
        children: choices
            .map((quadrant) => SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(quadrant),
                  child: Text('Cuadrante $quadrant'),
                ))
            .toList(),
      ),
    );
    if (selected != null && mounted) await _purchase('quadrant_locations', quadrant: selected);
  }

  Future<void> _completeMission(CurrentSecondaryMission mission) async {
    final enteredId = await showDialog<String>(
      context: context,
      builder: (_) => const _MissionCompletionDialog(),
    );
    if (!mounted || enteredId == null) return;
    setState(() => _buyingItem = 'mission');
    try {
      final result = await widget.rooms.completeSecondaryMission(roomId: widget.room.id, missionId: enteredId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      widget.gameRevision.value++;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_missionErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _buyingItem = null);
    }
  }

  String _missionErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('Ese ID no corresponde')) return 'ID de misión incorrecto.';
    if (message.contains('No tienes más misiones')) return 'No te quedan misiones secundarias.';
    return 'No se pudo completar la misión. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_GameActionsData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.assignment == null) return const SizedBox.shrink();
          final data = snapshot.data!;
          final settings = data.settings;
          return BottomAppBar(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: _compactActionButton(
                      filled: true,
                      onPressed: data.currentMission != null && _buyingItem == null
                          ? () => _completeMission(data.currentMission!)
                          : null,
                      icon: _buyingItem == 'mission'
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.task_alt_outlined),
                      label: 'Misión',
                    )),
                    const SizedBox(width: 4),
                    Expanded(child: _compactActionButton(
                      onPressed: settings.clueEnabled && _buyingItem == null ? () => _purchase('clue') : null,
                      icon: _buyingItem == 'clue' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lightbulb_outline),
                      label: 'Pista · 15',
                    )),
                    const SizedBox(width: 4),
                    Expanded(child: _compactActionButton(
                      onPressed: settings.quadrantEnabled && _buyingItem == null ? () => _purchase('quadrant') : null,
                      icon: _buyingItem == 'quadrant' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.grid_view_outlined),
                      label: 'Cuadr. · 10',
                    )),
                    const SizedBox(width: 4),
                    Expanded(child: _compactActionButton(
                      onPressed: settings.quadrantLocationsEnabled && _buyingItem == null && data.quadrants.isNotEmpty
                          ? () => _buyLocations(data.quadrants)
                          : null,
                      icon: _buyingItem == 'quadrant_locations'
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.location_on_outlined),
                      label: 'Ubic. · 25',
                    )),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _compactActionButton({required VoidCallback? onPressed, required Widget icon, required String label, bool filled = false}) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconTheme.merge(data: const IconThemeData(size: 17), child: icon),
      const SizedBox(width: 3),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
    ]);
    return filled
        ? FilledButton(onPressed: onPressed, style: _compactButtonStyle, child: child)
        : OutlinedButton(onPressed: onPressed, style: _compactButtonStyle, child: child);
  }

  static final _compactButtonStyle = ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 3, vertical: 8)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
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
    final source = await rootBundle.loadString('lib/resources/personajes.json');
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
    GameAreaLookup areas,
  ) async {
    try {
      final setup = GameSetup();
      final players = setup.initialize(
        players: room.players,
        tiles: tiles,
        charactersByName: characters,
      );
      final mystery = setup.selectMystery(players);
      final suspectRoomNames = mystery.suspectIds.map((participantId) {
        final player = players.firstWhere((player) => player.id == participantId);
        // Se guarda una entrada por cada sospechoso, incluso cuando coincidan.
        return areas.roomsFor(player.position!.name).firstOrNull ?? player.position!.name;
      }).toList();
      final mysteryWithLocations = GameMystery(
        thiefId: mystery.thiefId,
        accompliceIds: mystery.accompliceIds,
        suspectRoomNames: suspectRoomNames,
        secretWord: mystery.secretWord,
      );
      final secondarySource = await rootBundle.loadString('lib/resources/misionesSecundarias.json');
      List<SecondaryMissionDefinition> parseDefinitions(String source) {
        final json = jsonDecode(source) as Map<String, dynamic>;
        return json.entries
            .map((entry) => SecondaryMissionDefinition.fromJson(entry.key, entry.value as Map<String, dynamic>))
            .toList();
      }
      final secondaryMissions = setup.assignSecondaryMissions(
        // Los ficticios no tienen sesión para ver ni completar misiones.
        players: players.where((player) => !player.isFake).toList(),
        targets: players,
        missions: parseDefinitions(secondarySource),
        areas: areas,
      );
      await widget.rooms.saveAssignments(
        roomId: room.id,
        players: players,
        mystery: mysteryWithLocations,
        secondaryMissions: secondaryMissions,
      );
      if (!mounted) return;
      setState(() {
        _assignedPlayers = players;
        _mystery = mysteryWithLocations;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida iniciada.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmAndAssign(
    List<MapTile> tiles,
    GameRoom room,
    Map<String, CharacterProfile> characters,
    GameAreaLookup areas,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Iniciar o reiniciar la partida?'),
        content: const Text(
          'Se realizará un nuevo sorteo. Se perderán las asignaciones y las monedas actuales de todas las familias volverán a 100.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Sí, continuar')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _assignPositions(tiles, room, characters, areas);
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

  Future<void> _releaseCompassLocationClue() async {
    try {
      final result = await widget.rooms.releaseCompassLocationClue(widget.room.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
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
                  onPressed: () => _confirmAndAssign(tiles, room, characters, areas),
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(_assignedPlayers == null ? 'Asignar casillas' : 'Repartir de nuevo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Ver sorteo actual'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DrawResultsPage(room: room, rooms: widget.rooms, areas: areas),
                  )),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Revelar pista de ubicación del Compás'),
                  onPressed: _releaseCompassLocationClue,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.monetization_on_outlined),
                  label: const Text('Gestionar monedas de familias'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FamilyCoinsPage(room: room, rooms: widget.rooms),
                  )),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('Activar compras de jugadores'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PurchaseSettingsPage(room: room, rooms: widget.rooms),
                  )),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Programar eventos y probar avisos'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ScheduledEventsPage(room: room, rooms: widget.rooms),
                  )),
                ),
              ]),
            );
          },
        ),
      );
}

class ScheduledEventsPage extends StatefulWidget {
  const ScheduledEventsPage({super.key, required this.room, required this.rooms});

  final GameRoom room;
  final SupabaseRoomRepository rooms;

  @override
  State<ScheduledEventsPage> createState() => _ScheduledEventsPageState();
}

class _ScheduledEventsPageState extends State<ScheduledEventsPage> {
  late Future<List<ScheduledGameEvent>> _events;
  DateTime _selected = DateTime.now().add(const Duration(minutes: 2));
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _events = widget.rooms.roomScheduledEvents(widget.room.id);
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)), initialDate: _selected);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selected));
    if (time == null) return;
    setState(() => _selected = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _schedule() async {
    if (_selected.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige una hora futura.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final event = await widget.rooms.scheduleRandomEvent(roomId: widget.room.id, scheduledFor: _selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${event.title} programado.')));
      setState(() {
        _events = widget.rooms.roomScheduledEvents(widget.room.id);
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Eventos programados')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Cada evento se sortea al crearlo: ir a una estancia interior o “Achupé”.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _selectDateTime, icon: const Icon(Icons.schedule), label: Text('Hora: ${MaterialLocalizations.of(context).formatMediumDate(_selected)} · ${TimeOfDay.fromDateTime(_selected).format(context)}')),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _saving ? null : _schedule, icon: const Icon(Icons.notifications_active_outlined), label: const Text('Programar evento aleatorio')),
            const SizedBox(height: 20),
            Text('Historial', style: Theme.of(context).textTheme.titleMedium),
            Expanded(child: FutureBuilder<List<ScheduledGameEvent>>(
              future: _events,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(snapshot.error.toString());
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.isEmpty) return const Text('Aún no hay eventos programados.');
                return ListView(children: snapshot.data!.map((event) => ListTile(
                  leading: Icon(event.status == 'triggered' ? Icons.check_circle_outline : Icons.schedule_outlined),
                  title: Text(event.title),
                  subtitle: Text('${event.message}\n${event.scheduledFor}'),
                )).toList());
              },
            )),
          ]),
        ),
      );
}

class DrawResultsPage extends StatelessWidget {
  const DrawResultsPage({super.key, required this.room, required this.rooms, required this.areas});

  final GameRoom room;
  final SupabaseRoomRepository rooms;
  final GameAreaLookup areas;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sorteo actual')),
        body: FutureBuilder<List<Object?>>(
          future: Future.wait<Object?>([
            rooms.roomAssignments(room),
            rooms.roomClues(room.id),
            rooms.roomMystery(room.id),
            rooms.roomTeamQuadrants(room.id),
          ]),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final players = snapshot.data![0] as List<GamePlayer>;
            final clues = snapshot.data![1] as Map<String, String>;
            final mystery = snapshot.data![2] as GameMystery?;
            final quadrants = snapshot.data![3] as List<TeamQuadrant>;
            if (players.isEmpty) return const Center(child: Text('Todavía no se han asignado casillas.'));
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (mystery != null) _MysteryCard(mystery: mystery, players: players, areas: areas),
                if (quadrants.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cuadrantes de los equipos', style: Theme.of(context).textTheme.titleMedium),
                          ...Team.values.where((team) => quadrants.any((item) => item.team == team)).map(
                                (team) => Text(
                                  '${team.label}: ${quadrants.where((item) => item.team == team).map((item) => item.source == 'secret' ? '${item.quadrant} (secreto)' : item.quadrant).join(', ')}',
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ...players.map((player) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _teamColor(player.team!),
                        child: Text(player.team!.label.substring(0, 1)),
                      ),
                      title: Text('${player.name} - ${player.characterName}'),
                      subtitle: Text(
                        'Equipo ${player.team!.label}${player.familyName == null ? '' : ' - Familia ${player.familyName}'}${player.isAdmin ? ' - Admin' : ''}\nPista: ${clues[player.id] ?? 'Sin pista'}',
                      ),
                      isThreeLine: true,
                      trailing: Text(player.position!.name, style: Theme.of(context).textTheme.titleMedium),
                    )),
              ],
            );
          },
        ),
      );
}

class FamilyCoinsPage extends StatefulWidget {
  const FamilyCoinsPage({super.key, required this.room, required this.rooms});

  final GameRoom room;
  final SupabaseRoomRepository rooms;

  @override
  State<FamilyCoinsPage> createState() => _FamilyCoinsPageState();
}

class _FamilyCoinsPageState extends State<FamilyCoinsPage> {
  late Future<List<FamilyBalance>> _balances;

  @override
  void initState() {
    super.initState();
    _balances = widget.rooms.familyBalances(widget.room.id);
  }

  Future<void> _change(FamilyBalance balance, int sign) async {
    final amount = await _askAmount();
    if (amount == null) return;
    try {
      await widget.rooms.changeFamilyCoins(roomId: widget.room.id, balance: balance, amount: sign * amount);
      if (mounted) {
        setState(() {
          _balances = widget.rooms.familyBalances(widget.room.id);
        });
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<int?> _askAmount() async {
    return showDialog<int>(
      context: context,
      builder: (_) => const _CoinAmountDialog(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Monedas por familia')),
        body: FutureBuilder<List<FamilyBalance>>(
          future: _balances,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final balances = snapshot.data!;
            if (balances.isEmpty) return const Center(child: Text('Asigna las casillas para crear los saldos.'));
            return ListView(
              padding: const EdgeInsets.all(20),
              children: balances.map((balance) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _teamColor(balance.team),
                    child: Text(balance.team.label.substring(0, 1)),
                  ),
                  title: Text('${balance.team.label} - ${balance.familyName}'),
                  subtitle: Text('${balance.coins} monedas'),
                  trailing: Wrap(spacing: 4, children: [
                    IconButton(
                      tooltip: 'Quitar monedas',
                      onPressed: () => _change(balance, -1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Añadir monedas',
                      onPressed: () => _change(balance, 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ]),
                ),
              )).toList(),
            );
          },
        ),
      );
}

class _MissionCompletionDialog extends StatefulWidget {
  const _MissionCompletionDialog();

  @override
  State<_MissionCompletionDialog> createState() => _MissionCompletionDialogState();
}

class _MissionCompletionDialogState extends State<_MissionCompletionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Completar misión secundaria'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
          decoration: const InputDecoration(labelText: 'ID de la misión'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: _confirm, child: const Text('Confirmar')),
        ],
      );
}

class _CoinAmountDialog extends StatefulWidget {
  const _CoinAmountDialog();

  @override
  State<_CoinAmountDialog> createState() => _CoinAmountDialogState();
}

class _CoinAmountDialogState extends State<_CoinAmountDialog> {
  final _controller = TextEditingController(text: '10');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = int.tryParse(_controller.text.trim());
    if (amount == null || amount <= 0) return;
    // Se desmonta primero el campo (y su teclado) y el controlador se libera
    // desde dispose, cuando ya no mantiene dependencias del árbol de widgets.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cantidad de monedas'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Monedas'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: _confirm,
            child: const Text('Confirmar'),
          ),
        ],
      );
}

class PurchaseSettingsPage extends StatefulWidget {
  const PurchaseSettingsPage({super.key, required this.room, required this.rooms});

  final GameRoom room;
  final SupabaseRoomRepository rooms;

  @override
  State<PurchaseSettingsPage> createState() => _PurchaseSettingsPageState();
}

class _PurchaseSettingsPageState extends State<PurchaseSettingsPage> {
  late Future<PurchaseSettings> _settings;
  late Future<List<TeamQuadrant>> _quadrants;
  var _updating = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.rooms.purchaseSettings(widget.room.id);
    _quadrants = widget.rooms.roomTeamQuadrants(widget.room.id);
  }

  Future<void> _unlockSecretQuadrant(TeamQuadrant quadrant) async {
    setState(() => _updating = true);
    try {
      final result = await widget.rooms.unlockSecretTeamQuadrant(roomId: widget.room.id, team: quadrant.team);
      if (!mounted) return;
      setState(() {
        _quadrants = widget.rooms.roomTeamQuadrants(widget.room.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _updating = true);
    try {
      await widget.rooms.setPurchasesEnabled(roomId: widget.room.id, enabled: enabled);
      if (mounted) {
        setState(() {
          _settings = widget.rooms.purchaseSettings(widget.room.id);
        });
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _changeQuadrant({required Team team, required String quadrant, required bool add}) async {
    setState(() => _updating = true);
    try {
      final result = await widget.rooms.adminChangeTeamQuadrant(
        roomId: widget.room.id,
        team: team,
        quadrant: quadrant,
        add: add,
      );
      if (!mounted) return;
      setState(() {
        _quadrants = widget.rooms.roomTeamQuadrants(widget.room.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _showAddQuadrantDialog() async {
    var team = Team.red;
    var quadrant = 'A';
    final selection = await showDialog<(Team, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Añadir cuadrante a un equipo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Team>(
                value: team,
                decoration: const InputDecoration(labelText: 'Equipo'),
                items: Team.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                onChanged: (value) => setDialogState(() => team = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: quadrant,
                decoration: const InputDecoration(labelText: 'Cuadrante'),
                items: const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']
                    .map((item) => DropdownMenuItem(value: item, child: Text('Cuadrante $item')))
                    .toList(),
                onChanged: (value) => setDialogState(() => quadrant = value!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(context).pop((team, quadrant)), child: const Text('Añadir')),
          ],
        ),
      ),
    );
    if (selection != null && mounted) {
      await _changeQuadrant(team: selection.$1, quadrant: selection.$2, add: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Compras de jugadores')),
        body: FutureBuilder<PurchaseSettings>(
          future: _settings,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorPage(message: snapshot.error.toString());
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final settings = snapshot.data!;
            return FutureBuilder<List<TeamQuadrant>>(
              future: _quadrants,
              builder: (context, quadrantsSnapshot) {
                final secretQuadrants = (quadrantsSnapshot.data ?? const <TeamQuadrant>[])
                    .where((quadrant) => quadrant.source == 'secret')
                    .toList();
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Activa todas las compras a la vez. Cada vez que se abre una ronda, el ladrón y sus dos cómplices pueden hacer un daño cada uno.'),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Habilitar compras y daños'),
                      subtitle: const Text('Pistas · cuadrantes · ubicaciones'),
                      value: settings.clueEnabled && settings.quadrantEnabled && settings.quadrantLocationsEnabled,
                      onChanged: _updating ? null : _setEnabled,
                    ),
                    const Divider(height: 32),
                    Text('Cuadrantes secretos conseguidos', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Márcalo solo cuando ese equipo lo haya conseguido fuera de la app. Así podrán comprar sus ubicaciones.'),
                    if (quadrantsSnapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('No se pudieron cargar los cuadrantes: ${quadrantsSnapshot.error}'),
                      )
                    else if (!quadrantsSnapshot.hasData)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (secretQuadrants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No hay cuadrantes secretos pendientes.'),
                      )
                    else
                      ...secretQuadrants.map(
                        (quadrant) => Card(
                          child: ListTile(
                            title: Text('Equipo ${quadrant.team.label}'),
                            subtitle: Text('Cuadrante secreto: ${quadrant.quadrant}'),
                            trailing: FilledButton(
                              onPressed: _updating ? null : () => _unlockSecretQuadrant(quadrant),
                              child: const Text('Habilitar'),
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 32),
                    Text('Cambios de cuadrantes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Añade o retira cuadrantes por cambios y robos realizados durante la partida.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _updating ? null : _showAddQuadrantDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir cuadrante'),
                    ),
                    if (quadrantsSnapshot.hasData)
                      ...Team.values.map((team) {
                        final teamQuadrants = quadrantsSnapshot.data!.where((item) => item.team == team).toList();
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Equipo ${team.label}', style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 4),
                                if (teamQuadrants.isEmpty)
                                  const Text('No tiene cuadrantes disponibles.')
                                else
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: teamQuadrants
                                        .map((item) => InputChip(
                                              label: Text(item.quadrant),
                                              tooltip: 'Origen: ${item.source}',
                                              onDeleted: _updating
                                                  ? null
                                                  : () => _changeQuadrant(team: team, quadrant: item.quadrant, add: false),
                                            ))
                                        .toList(),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
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
            if (mystery.suspectRoomNames.length == 3) ...[
              const SizedBox(height: 8),
              Text('Pista guardada de estancias: ${mystery.suspectRoomNames.join(', ')}.'),
            ],
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
