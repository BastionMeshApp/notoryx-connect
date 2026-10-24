import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'beacon_page.dart';
import 'map_page.dart';
import 'field_tools_page.dart';
import 'home_page.dart';
import 'services/bastion_field_log.dart';
import 'services/bastion_background_service.dart';
import 'services/bastion_bot_guard.dart';
import 'services/bastion_preferences.dart';
import 'phone_backup_page.dart';
import 'privacy_page.dart';
import 'radio_backup_page.dart';
import 'services/bastion_message_search.dart';
import 'mesh_tools_page.dart';
import 'node_detail_page.dart';
import 'radio_settings_page.dart';
import 'services/bastion_tile_cache.dart';
import 'traceroute_page.dart';
import 'services/meshtastic_ble_discovery.dart';
import 'services/meshtastic_connection_controller.dart';
import 'services/bastion_field_alerts.dart';
import 'services/bastion_phone_position.dart';
import 'services/meshtastic_messaging_service.dart';
import 'services/meshtastic_radio_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('licenses/meshtastic-protobufs-GPL-3.0.txt');
    yield LicenseEntryWithLineBreaks(['Meshtastic protobufs'], text);
  });
  await BastionTileCache.initialize();
  await BastionPreferences.instance.load();
  await BastionFieldLog.instance.load();
  await BastionBotGuard.instance.load();
  runApp(const BastionApp());
}

class BastionApp extends StatelessWidget {
  const BastionApp({super.key});
  /// NOTORYX orange from the app icon; the accent in the dark theme.
  static const signal = Color(0xFFFC7202);

  /// The same hue, darkened so text and icons keep 4.5:1 contrast on the
  /// light theme's surfaces (#FC7202 is only about 2.6:1 there).
  static const signalOnLight = Color(0xFFAC4E01);
  static const panel = Color(0xFF151713);

  /// The accent for the current theme.
  static Color accentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? signal : signalOnLight;

  static ThemeData appearance(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    // Text on the accent: black on bright orange (7.6:1), white on the
    // deeper light-theme orange (5.5:1).
    final colors = ColorScheme.fromSeed(seedColor: signal, brightness: brightness).copyWith(
      primary: dark ? signal : signalOnLight,
      onPrimary: dark ? Colors.black : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: dark ? const Color(0xFF0D0F0C) : colors.surface,
      disabledColor: colors.onSurfaceVariant,
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? colors.onSurfaceVariant : null),
      )),
      listTileTheme: ListTileThemeData(
        textColor: colors.onSurface, iconColor: colors.onSurfaceVariant,
      ),
      appBarTheme: AppBarTheme(backgroundColor: dark ? const Color(0xFF0D0F0C) : colors.surface),
      cardTheme: CardThemeData(
        color: dark ? panel : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: BastionPreferences.instance,
    builder: (context, _) => MaterialApp(
      title: 'NOTORYX Connect', debugShowCheckedModeBanner: false,
      theme: appearance(Brightness.light), darkTheme: appearance(Brightness.dark),
      themeMode: BastionPreferences.instance.theme,
      home: const BastionShell(),
    ),
  );
}

class BastionShell extends StatefulWidget {
  const BastionShell({super.key});
  @override
  State<BastionShell> createState() => _BastionShellState();
}

class _BastionShellState extends State<BastionShell> {
  int index = 0;
  final ble = MeshtasticBleDiscovery();
  final radio = MeshtasticRadioCoordinator();
  bool botMode = false;
  String awayReply = MeshtasticMessagingService.defaultAwayReply;

  static const labels = ['HOME', 'NODES', 'CHATS', 'MAP', 'TOOLS', 'SETTINGS'];
  static const icons = [
    Icons.shield_outlined, Icons.hub_outlined, Icons.chat_bubble_outline, Icons.map_outlined,
    Icons.build_outlined, Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _setUpShortcuts();
  }

  /// Long-press shortcuts on the app icon, each opening a tab.
  void _setUpShortcuts() {
    if (kIsWeb || !Platform.isAndroid) return;
    const tabs = {'home': 0, 'nodes': 1, 'chats': 2, 'map': 3};
    try {
      const actions = QuickActions();
      actions.initialize((type) {
        final tab = tabs[type];
        if (tab != null && mounted) setState(() => index = tab);
      });
      actions.setShortcutItems(const [
        ShortcutItem(type: 'home', localizedTitle: 'Check in / SOS'),
        ShortcutItem(type: 'chats', localizedTitle: 'Chats'),
        ShortcutItem(type: 'nodes', localizedTitle: 'Nodes'),
        ShortcutItem(type: 'map', localizedTitle: 'Map'),
      ]).catchError((Object _) {});
    } catch (_) {
      // Shortcuts are a convenience; the app works without them.
    }
  }

  @override
  void dispose() {
    ble.dispose();
    radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(38) + 18,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NOTORYX', style: TextStyle(fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.primary, letterSpacing: 2)),
        const Text('CONNECT', style: TextStyle(fontSize: 10, letterSpacing: 1.4)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AnimatedBuilder(
            animation: radio,
            builder: (context, _) => MediaQuery.textScalerOf(context).scale(14) > 20
                ? Tooltip(message: _connectionLabel(radio.connection.state), child: Icon(
                    radio.isReady ? Icons.bluetooth_connected : Icons.bluetooth_disabled))
                : Chip(
              avatar: Icon(
                radio.isReady ? Icons.bluetooth_connected : Icons.radio_button_checked,
                size: 16,
              ),
              label: Text(_connectionLabel(radio.connection.state)),
              side: BorderSide(color: Colors.white.withValues(alpha: .15)),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(child: IndexedStack(index: index, children: [
      HomePage(radio: radio, onConnect: () => setState(() => index = 1)),
      _NodesPage(discovery: ble, radio: radio, onOpenTools: () => setState(() => index = 4)),
      BastionChatsPage(
        radio: radio,
        botMode: botMode,
        awayReply: awayReply,
        onBotModeChanged: (value) {
          setState(() => botMode = value);
          radio.configureBot(enabled: value, reply: awayReply);
        },
        onAwayReplyChanged: (value) {
          setState(() => awayReply = value);
          radio.configureBot(enabled: botMode, reply: value);
        },
      ),
      MapPage(radio: radio),
      _ToolsPage(discovery: ble, radio: radio),
      _SettingsPage(radio: radio),
    ])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: [
        for (var i = 0; i < labels.length; i++)
          NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
      ],
    ),
  );
}

class _NodesPage extends StatelessWidget {
  const _NodesPage({
    required this.discovery,
    required this.radio,
    required this.onOpenTools,
  });
  final MeshtasticBleDiscovery discovery;
  final MeshtasticRadioCoordinator radio;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([discovery, radio, BastionPreferences.instance]),
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Header(icon: Icons.radar, title: 'MESH COMMAND',
          detail: 'Find a nearby radio, inspect Bluetooth signal strength, and prepare for a verified Meshtastic session.'),
        const SizedBox(height: 14),
        if (BastionPreferences.instance.statistics)
        Row(children: [
          Expanded(child: _Stat(label: 'BLE DEVICES', value: '${discovery.results.length}')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(label: 'MESH NODES', value: '${radio.nodes.length}')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(
            label: 'STATUS',
            value: _connectionTileLabel(radio.connection.state),
          )),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: discovery.scanning ? null : discovery.scan,
          icon: Icon(discovery.scanning ? Icons.hourglass_top : Icons.bluetooth_searching),
          label: Text(discovery.scanning ? 'SCANNING…' : 'SCAN FOR RADIOS'),
        ),
        if (discovery.scanning)
          TextButton(onPressed: discovery.stop, child: const Text('STOP SCAN')),
        if (discovery.error != null)
          _Notice(text: discovery.error!, icon: Icons.warning_amber),
        const SizedBox(height: 10),
        if (discovery.results.isEmpty)
          const _EmptyState(icon: Icons.bluetooth_disabled,
            title: 'No radios discovered yet',
            detail: 'Tap SCAN FOR RADIOS. Nearby BLE devices will appear here with live RSSI.')
        else
          for (final item in discovery.results)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.router)),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${item.id}\n${item.advertisesMeshtastic ? 'Meshtastic service advertised' : _rssiLabel(item.rssi)}',
              ),
              isThreeLine: true,
              trailing: (radio.isReady || radio.isReconnecting) &&
                      radio.connection.deviceName == item.name
                  ? IconButton(
                      tooltip: 'Disconnect',
                      onPressed: radio.busy ? null : radio.disconnect,
                      icon: const Icon(Icons.link_off),
                    )
                  : FilledButton(
                      onPressed: radio.busy
                          ? null
                          : () async {
                              try {
                                await radio.connect(item);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Connection failed: $error')),
                                  );
                                }
                              }
                            },
                      child: const Text('CONNECT', maxLines: 1, softWrap: false),
                    ),
            )),
        if (radio.connection.error != null)
          _Notice(text: radio.connection.error!, icon: Icons.error_outline),
        if (radio.backgroundProblem != null)
          _Notice(text: radio.backgroundProblem!, icon: Icons.warning_amber),
        if (radio.nodes.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('LIVE MESH NODES',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 6),
          for (final node in radio.nodes)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.cell_tower)),
              title: Text(node.displayName),
              subtitle: Text([
                if (node.shortName?.isNotEmpty ?? false) node.shortName!,
                node.id ?? '!${node.num.toRadixString(16).padLeft(8, '0')}',
              ].join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NodeDetailPage(radio: radio, nodeNum: node.num),
              )),
            )),
        ],
        if (radio.isReady && BastionPreferences.instance.meshHealth) ...[
          const SizedBox(height: 14),
          const Text('MESH HEALTH • LIVE SESSION',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Stat(label: 'KNOWN NODES',
              value: '${radio.nodes.length}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'MESSAGES',
              value: '${radio.messages.length}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'PENDING',
              value: '${radio.pendingMessageCount}')),
          ]),
          const SizedBox(height: 10),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RECEIVE SIGNAL • TEXT PACKETS',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Received: ${radio.receivedTextPackets} • Latest SNR: '
                '${radio.latestSnr == null ? 'Waiting for packet' : '${radio.latestSnr!.toStringAsFixed(1)} dB'}'),
              const SizedBox(height: 10),
              if (radio.snrHistory.isNotEmpty)
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final snr in radio.snrHistory.reversed.take(20).toList().reversed)
                    Tooltip(message: '${snr.toStringAsFixed(1)} dB',
                      child: Container(
                        width: 10,
                        height: 12 + (snr + 20).clamp(0, 40).toDouble(),
                        decoration: BoxDecoration(
                          color: BastionApp.accentOf(context),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )),
                ])
              else
                const Text('Send a message from another node to start the SNR history.'),
            ]),
          )),
          const SizedBox(height: 6),
          const _Notice(
            text: 'SNR values come from received text packets only. '
              'RSSI and delivery-rate monitoring are not available yet.',
            icon: Icons.monitor_heart_outlined,
          ),
        ],
        if (radio.nodeDex.isNotEmpty && BastionPreferences.instance.encounters) ...[
          const SizedBox(height: 18),
          const Text('NODEDEX • SAVED ENCOUNTERS',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 6),
          for (final record in radio.nodeDex)
            Card(child: ListTile(
              leading: Icon(record.favorite ? Icons.star : Icons.person_pin_circle_outlined,
                color: record.favorite ? BastionApp.accentOf(context) : null),
              title: Text(record.displayName),
              subtitle: Text('Encounters: ${record.encounters} • Last seen: ${record.lastSeen.toLocal()}'
                '\n${record.note.isEmpty ? 'Tap to add field notes' : record.note}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: record.favorite ? 'Remove favorite' : 'Favorite node',
                icon: Icon(record.favorite ? Icons.star : Icons.star_border),
                onPressed: () => radio.setNodeFavorite(record.num, !record.favorite),
              ),
              onTap: () async {
                final editor = TextEditingController(text: record.note);
                final note = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text('Field notes • ${record.displayName}'),
                    content: TextField(
                      controller: editor,
                      autofocus: true,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        hintText: 'Location, antenna, observations…',
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('CANCEL')),
                      FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text),
                        child: const Text('SAVE')),
                    ],
                  ),
                );
                if (note != null) await radio.setNodeNote(record.num, note);
              },
            )),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: onOpenTools,
          icon: const Icon(Icons.construction), label: const Text('OPEN FIELD TOOLS')),
        _Notice(
          text: radio.isReady
              ? 'Verified Meshtastic session ready. Live NodeDB updates will appear above.'
              : 'Scan, then tap CONNECT on a radio. NOTORYX Connect verifies the Meshtastic service, performs the PhoneAPI handshake, and synchronizes NodeDB before marking the session ready.',
          icon: radio.isReady ? Icons.verified_outlined : Icons.info_outline),
      ],
    ),
  );
}

class BastionChatsPage extends StatefulWidget {
  const BastionChatsPage({
    required this.radio,
    required this.botMode,
    required this.awayReply,
    required this.onBotModeChanged,
    required this.onAwayReplyChanged,
  });
  final MeshtasticRadioCoordinator radio;
  final bool botMode;
  final String awayReply;
  final ValueChanged<bool> onBotModeChanged;
  final ValueChanged<String> onAwayReplyChanged;

  @override
  State<BastionChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<BastionChatsPage> {
  late final TextEditingController reply =
      TextEditingController(text: widget.awayReply);
  final composer = TextEditingController();
  int destination = 0xffffffff;
  int channel = 0;
  final search = TextEditingController();

  /// Unsent text per conversation, so switching chats doesn't lose it.
  final Map<String, String> _drafts = {};
  String get _draftKey => destination == 0xffffffff ? 'ch$channel' : 'dm$destination';

  @override
  void initState() {
    super.initState();
    unawaited(_loadDrafts());
  }

  Future<void> _loadDrafts() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_draftsKey);
      if (raw == null || !mounted) return;
      _drafts.addAll((jsonDecode(raw) as Map).cast<String, String>());
      if (composer.text.isEmpty) composer.text = _drafts[_draftKey] ?? '';
    } catch (_) {
      // Drafts are a convenience; a damaged store is ignored.
    }
  }

  static const _draftsKey = 'bastion.drafts.v1';

  void _saveDraft() {
    final text = composer.text;
    if (text.trim().isEmpty) {
      _drafts.remove(_draftKey);
    } else {
      _drafts[_draftKey] = text;
    }
    try {
      unawaited(SharedPreferencesAsync().setString(_draftsKey, jsonEncode(_drafts))
          .catchError((Object _) {}));
    } catch (_) {
      // Drafts are a convenience; storage may be unavailable.
    }
  }

  /// Switches conversation, keeping each one's unsent text.
  void _switchTo({int? newDestination, int? newChannel}) {
    _saveDraft();
    setState(() {
      destination = newDestination ?? destination;
      channel = newChannel ?? channel;
      composer.text = _drafts[_draftKey] ?? '';
    });
  }

  @override
  void dispose() {
    _saveDraft();
    reply.dispose();
    composer.dispose();
    search.dispose();
    super.dispose();
  }

  static const _reactionChoices = ['👍', '❤️', '😂', '😮', '😢', '✅', '🙏'];

  Future<void> _react(BastionChatMessage message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('React', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: [
            for (final e in _reactionChoices)
              IconButton(
                tooltip: 'React $e',
                onPressed: () => Navigator.pop(context, e),
                icon: Text(e, style: const TextStyle(fontSize: 28)),
              ),
          ]),
        ]),
      )),
    );
    if (emoji == null || !mounted) return;
    try {
      await widget.radio.sendReaction(message, emoji);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is StateError ? error.message : 'Reaction not sent: $error')));
      }
    }
  }

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? composer.text).trim();
    if (text.isEmpty) return;
    try {
      await widget.radio.sendText(text: text, destination: destination, channel: channel);
      if (quickText == null) {
        composer.clear();
        _saveDraft();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message not sent: $error')),
        );
      }
    }
  }

  String _nodeName(int nodeNum) {
    for (final node in widget.radio.nodes) {
      if (node.num == nodeNum) return node.displayName;
    }
    return '!${nodeNum.toRadixString(16).padLeft(8, '0')}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.radio,
    builder: (context, _) {
      final all = widget.radio.messages;
      // Reactions show under the message they react to, not on their own.
      final messages = [for (final m in all) if (!m.isReaction) m];
      final reactions = <int, List<BastionChatMessage>>{};
      for (final m in all) {
        if (m.isReaction && m.replyId != null) (reactions[m.replyId!] ??= []).add(m);
      }
      final matches = BastionMessageSearch.filter(messages, search.text,
          (message) => message.text);
      final channels = widget.radio.channelMetadata.where((c) => c.role != 0).toList();
      if (channels.isNotEmpty && !channels.any((c) => c.index == channel)) {
        channel = channels.first.index;
      }
      if (destination != 0xffffffff && !widget.radio.nodes.any((n) => n.num == destination)) {
        destination = 0xffffffff;
      }
      final connected = widget.radio.isReady;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            icon: Icons.forum_outlined,
            title: 'COMMS',
            detail: connected
                ? 'Live Meshtastic messaging is ready.'
                : 'Messages can be queued offline and send automatically when the radio is connected.',
          ),
          if (widget.radio.messageStorageProblem case final problem?)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.sd_card_alert_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer),
                title: Text('Message storage problem',
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                subtitle: Text(problem,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(
              label: 'LINK',
              value: connected ? 'ONLINE' : 'OFFLINE',
            )),
            const SizedBox(width: 10),
            Expanded(child: _Stat(
              label: 'MESSAGES',
              value: messages.length.toString(),
            )),
            const SizedBox(width: 10),
            Expanded(child: _Stat(
              label: 'QUEUED',
              value: widget.radio.pendingMessageCount.toString(),
            )),
          ]),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DESTINATION',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey(destination),
                initialValue: destination,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cell_tower),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 0xffffffff,
                    child: Text('Broadcast'),
                  ),
                  for (final node in widget.radio.nodes)
                    DropdownMenuItem(
                      value: node.num,
                      child: Text('DM • ${node.displayName}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _switchTo(newDestination: value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('channel-$channel'),
                initialValue: channel,
                decoration: const InputDecoration(labelText: 'Channel', border: OutlineInputBorder()),
                items: channels.isEmpty
                    ? [const DropdownMenuItem(value: 0, child: Text('Channel 0 • Broadcast')),
                       if (channel != 0) DropdownMenuItem(value: channel,
                           child: Text('Channel $channel • Offline'))]
                    : [for (final c in channels) DropdownMenuItem(value: c.index,
                        child: Text('Channel ${c.index} • ${c.name.isEmpty ? 'Default' : c.name}'))],
                onChanged: (value) { if (value != null) _switchTo(newChannel: value); },
              ),
            ]),
          )),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              TextField(
                controller: composer,
                maxLength: 228,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: destination == 0xffffffff
                      ? 'Message Channel $channel'
                      : 'Message ${_nodeName(destination)}',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
                onChanged: (_) => _saveDraft(),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  label: const Text('SEND'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final quick in const [
                  'Copy',
                  'On my way',
                  'Need assistance',
                  'What is your position?',
                ])
                  ActionChip(
                    label: Text(quick),
                    onPressed: () => _send(quick),
                  ),
              ]),
            ]),
          )),
          TextField(
            controller: search,
            decoration: const InputDecoration(labelText: 'Search message history',
                prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          if (messages.isNotEmpty && matches.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No messages match your search.')),
          if (messages.isEmpty)
            const _EmptyState(
              icon: Icons.mark_chat_unread_outlined,
              title: 'No mesh messages yet',
              detail: 'Incoming channel and direct messages will appear here after a radio is connected.',
            )
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text('MESSAGE TIMELINE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
            ),
            for (final message in matches.reversed)
              Card(child: ListTile(
                onLongPress: () => _react(message),
                leading: CircleAvatar(
                  child: Icon(message.direction == BastionMessageDirection.outgoing
                      ? Icons.north_east : Icons.south_west),
                ),
                title: Text(message.text),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([
                    message.direction == BastionMessageDirection.outgoing
                        ? (message.isBroadcast
                            ? 'You → Channel ${message.channel}'
                            : 'You → ${_nodeName(message.to)}')
                        : (message.isBroadcast
                            ? '${_nodeName(message.from)} → Channel ${message.channel}'
                            : '${_nodeName(message.from)} → You'),
                    // Heard over the internet, not over the air.
                    if (message.viaMqtt) 'via MQTT',
                  ].join(' • ')),
                  if (reactions[message.packetId] case final rs?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Semantics(
                        label: 'Reactions: ${[for (final r in rs) '${r.text} from ${r.direction == BastionMessageDirection.outgoing ? 'you' : _nodeName(r.from)}'].join(', ')}',
                        excludeSemantics: true,
                        child: Wrap(spacing: 6, children: [
                          for (final e in {for (final r in rs) r.text}.toList())
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('$e ${rs.where((r) => r.text == e).length}'),
                            ),
                        ]),
                      ),
                    ),
                ]),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_deliveryIcon(message.deliveryState), size: 18),
                    const SizedBox(height: 3),
                    Text(_deliveryLabel(message.deliveryState),
                      style: const TextStyle(fontSize: 9)),
                  ],
                ),
              )),
          ],
          const SizedBox(height: 10),
          Card(child: SwitchListTile(
            secondary: Icon(Icons.smart_toy_outlined,
              color: BastionApp.accentOf(context)),
            title: const Text('BOT MODE',
              style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.radio.botProblem ?? (widget.botMode
                ? 'ACTIVE • DM auto-reply + !help / !status • quiet hours + airtime limits'
                : 'Automatic replies are off')),
            value: widget.botMode,
            onChanged: widget.onBotModeChanged,
          )),
          Card(child: ExpansionTile(
            leading: Icon(Icons.tune, color: BastionApp.accentOf(context)),
            title: const Text('BOT RESPONSE',
              style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: reply,
                maxLines: 3,
                maxLength: 160,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Message to send while Bot Mode is active',
                ),
                onChanged: widget.onAwayReplyChanged,
              ),
            ],
          )),
        ],
      );
    },
  );
}

IconData _deliveryIcon(BastionDeliveryState state) => switch (state) {
  BastionDeliveryState.received => Icons.call_received,
  BastionDeliveryState.queued => Icons.schedule,
  BastionDeliveryState.sent => Icons.check,
  BastionDeliveryState.delivered => Icons.done_all,
  BastionDeliveryState.failed => Icons.error_outline,
};

String _deliveryLabel(BastionDeliveryState state) => switch (state) {
  BastionDeliveryState.received => 'RX',
  BastionDeliveryState.queued => 'QUEUED',
  BastionDeliveryState.sent => 'SENT',
  BastionDeliveryState.delivered => 'DELIVERED',
  BastionDeliveryState.failed => 'FAILED',
};

class _ToolsPage extends StatefulWidget {
  const _ToolsPage({required this.discovery, required this.radio});
  final MeshtasticBleDiscovery discovery;
  final MeshtasticRadioCoordinator radio;
  @override
  State<_ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<_ToolsPage> {
  final battery = TextEditingController(text: '3000');
  final draw = TextEditingController(text: '100');
  double? runtime;
  final checked = <String>{};
  static const checklist = [
    'Radio charged', 'Antenna attached', 'Region configured',
    'Primary channel verified', 'GPS / position policy checked',
  ];

  @override
  void dispose() { battery.dispose(); draw.dispose(); super.dispose(); }

  void calculate() {
    final mah = double.tryParse(battery.text);
    final ma = double.tryParse(draw.text);
    setState(() => runtime = mah != null && ma != null && ma > 0 ? mah / ma : null);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.construction, title: 'FIELD TOOLS',
        detail: 'Practical utilities you can use before and during a deployment.'),
      const SizedBox(height: 14),
      Card(child: ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: const Text('Incident log, emergency templates & coverage'),
        subtitle: const Text('Saved field records and exports'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => FieldToolsPage(radio: widget.radio))),
      )),
      Card(child: ExpansionTile(
        leading: Icon(Icons.battery_charging_full, color: BastionApp.accentOf(context)),
        title: const Text('BATTERY RUNTIME', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Estimate runtime from capacity and average current'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: battery,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Battery (mAh)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: draw,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Avg draw (mA)'))),
          ]),
          const SizedBox(height: 12),
          FilledButton(onPressed: calculate, child: const Text('CALCULATE')),
          if (runtime != null)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('Estimated runtime: ${runtime!.toStringAsFixed(1)} hours',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: BastionApp.accentOf(context)))),
        ],
      )),
      Card(child: ExpansionTile(
        leading: Icon(Icons.signal_cellular_alt, color: BastionApp.accentOf(context)),
        title: Text('RSSI FIELD REFERENCE', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Quick Bluetooth signal-strength guide'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _ReferenceRow(value: '−50 dBm', label: 'Excellent / very close'),
          _ReferenceRow(value: '−60 dBm', label: 'Strong'),
          _ReferenceRow(value: '−70 dBm', label: 'Usable'),
          _ReferenceRow(value: '−80 dBm', label: 'Weak'),
          _ReferenceRow(value: '≤ −90', label: 'Very weak / unstable'),
        ],
      )),
      Card(child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.checklist, color: BastionApp.accentOf(context)),
        title: const Text('DEPLOYMENT CHECKLIST', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${checked.length}/${checklist.length} ready'),
        children: [
          for (final item in checklist)
            CheckboxListTile(
              dense: true, title: Text(item), value: checked.contains(item),
              onChanged: (value) => setState(() {
                value == true ? checked.add(item) : checked.remove(item);
              }),
            ),
        ],
      )),
      Card(child: ListTile(
        leading: Icon(Icons.bluetooth_searching, color: BastionApp.accentOf(context)),
        title: const Text('RADIO SCANNER', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${widget.discovery.results.length} BLE devices currently discovered'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.discovery.scanning ? null : widget.discovery.scan,
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.network_check),
        title: const Text('RANGE TEST', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Log packets from a range test sender with signal and distance'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MeshToolsPage(radio: widget.radio),
        )),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('STORE & FORWARD', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Replay messages you missed from a router'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MeshToolsPage(radio: widget.radio, initialTab: 1),
        )),
      )),
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) => Card(child: ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: const Text('MESH BEACONS', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(widget.radio.beacons.isEmpty
              ? 'Hear mesh invitations nearby and send your own'
              : '${widget.radio.beacons.length} heard • send your own'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => BeaconPage(radio: widget.radio),
          )),
        )),
      ),
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) => Card(child: ListTile(
          enabled: widget.radio.isReady,
          leading: const Icon(Icons.route),
          title: const Text('TRACEROUTE', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(widget.radio.isReady
            ? 'Show the relay path to a node and back'
            : 'Connect to a radio to trace routes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TraceroutePage(radio: widget.radio),
          )),
        )),
      ),
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) {
          final readings = widget.radio.deviceTelemetry.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return Card(child: ExpansionTile(
            leading: Icon(Icons.monitor_heart_outlined, color: BastionApp.accentOf(context)),
            title: const Text('LIVE TELEMETRY',
              style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.radio.isReady
              ? '${readings.length} nodes reporting device metrics'
              : 'Connect to a radio to receive telemetry'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (readings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No device telemetry received yet. Metrics appear when nodes transmit them.'),
                ),
              for (final entry in readings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Node !${entry.key.toRadixString(16).padLeft(8, '0')}'),
                  subtitle: Text([
                    if (entry.value.batteryLevel != null)
                      'Battery ${entry.value.batteryLevel}%',
                    if (entry.value.voltage != null)
                      'Voltage ${entry.value.voltage!.toStringAsFixed(2)} V',
                    if (entry.value.channelUtilization != null)
                      'Channel ${entry.value.channelUtilization!.toStringAsFixed(1)}%',
                    if (entry.value.airUtilTx != null)
                      'TX airtime ${entry.value.airUtilTx!.toStringAsFixed(1)}%',
                  ].join(' · ')),
                ),
            ],
          ));
        },
      ),
    ],
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.radio});
  final MeshtasticRadioCoordinator radio;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.tune, title: 'SETTINGS',
        detail: 'Field behavior, connection preferences and build information.'),
      const SizedBox(height: 14),
      const BastionAppearanceCard(),
      const _MessagesCard(),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) => Card(child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(Icons.settings_input_antenna, color: BastionApp.accentOf(context)),
          title: const Text('RADIO CONFIGURATION',
            style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(radio.canAdminister
            ? 'Radio connected • settings can be changed'
            : 'Connect to a radio to view and change its settings'),
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Node identity'),
              subtitle: Text(radio.localNode == null
                ? 'Waiting for this radio\'s node information'
                : 'Long: ${radio.localNode!.longName ?? 'Not reported'}\n'
                  'Short: ${radio.localNode!.shortName ?? 'Not reported'}\n'
                  'ID: ${radio.localNode!.id ?? 'Not reported'}'),
              isThreeLine: true,
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Change radio settings'),
              subtitle: const Text('Owner, LoRa, channels, device role and position'),
              enabled: radio.canAdminister,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RadioSettingsPage(radio: radio),
              )),
            ),
            ListTile(title: const Text('Device & LoRa'),
              subtitle: Text(radio.loraSettings.isEmpty
                ? '${radio.radioConfigCount} configuration messages • LoRa values unavailable'
                : radio.loraSettings.join('\n'))),
            ListTile(
              title: const Text('Channels'),
              subtitle: Text(radio.channelSettings.isEmpty
                ? '${radio.channelConfigCount} channel messages • details unavailable'
                : radio.channelSettings.join('\n')),
            ),
            ListTile(title: const Text('Modules'),
              subtitle: Text('${radio.moduleConfigCount} module messages received • edit through radio settings')),
          ],
        )),
      ),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) {
          final sent = radio.lastPhonePositionSent;
          final status = radio.locationShareProblem ??
              (!radio.sharePhoneLocation
                  ? 'Off. Your phone location is never sent.'
                  : !radio.isReady
                      ? 'On. Starts when a radio is connected.'
                      : sent == null
                          ? 'On. Waiting for a GPS fix.'
                          : 'On. Last sent ${sent.toLocal().toString().substring(11, 16)}.');
          return Card(child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: const Text('Share phone location with mesh'),
              subtitle: Text('$status\nThe radio broadcasts it when it has no GPS of its own. '
                  'Updates every 5 min, or sooner when you move.'),
              isThreeLine: true,
              value: radio.sharePhoneLocation,
              onChanged: (value) => radio.setSharePhoneLocation(value),
            ),
            ListTile(
              leading: const Icon(Icons.blur_on),
              title: const Text('Location precision'),
              subtitle: const Text('Approximate positions are rounded on this phone before they are sent'),
              trailing: DropdownButton<int>(
                value: radio.locationPrecision,
                items: [for (final e in BastionPhonePositionSharer.precisionChoices.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) { if (v != null) radio.setLocationPrecision(v); },
              ),
            ),
          ]));
        },
      ),
      Card(child: ListTile(
        leading: const Icon(Icons.enhanced_encryption_outlined),
        title: const Text('Encrypted radio backup / restore'),
        subtitle: const Text('Password-protected settings and channel keys'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RadioBackupPage(radio: radio))),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.phone_android_outlined),
        title: const Text('Phone data backup / restore'),
        subtitle: const Text('Chats, NodeDex, waypoints, field records and settings, for moving to a new phone'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PhoneBackupPage(radio: radio))),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Privacy & data'),
        subtitle: const Text('What is stored and sent; delete chat history or all phone data'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PrivacyPage(radio: radio))),
      )),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) => _BackgroundCard(radio: radio),
      ),
      const _MapCacheCard(),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) => _FieldAlertsCard(radio: radio),
      ),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) => Card(child: SwitchListTile(
          secondary: const Icon(Icons.battery_saver_outlined),
          title: const Text('Low-power field mode'),
          subtitle: const Text('Shared phone location uses balanced GPS accuracy and '
              'updates every 15 min, or after 200 m of movement. '
              'Radio link and coverage recording are unchanged.'),
          isThreeLine: true,
          value: radio.lowPowerMode,
          onChanged: (value) => radio.setLowPowerMode(value)))),
      const Card(child: ListTile(
        leading: Icon(Icons.bluetooth), title: Text('Preferred transport'),
        subtitle: Text('Bluetooth LE'), trailing: Text('BLE'))),
      Card(child: ListTile(
        leading: Icon(Icons.security_outlined), title: Text('Safety mode'),
        subtitle: Text('No unverified device is treated as a mesh node'),
        trailing: Icon(Icons.verified_user_outlined, color: BastionApp.accentOf(context)))),
      Card(child: ListTile(
        leading: const Icon(Icons.description_outlined), title: const Text('Third-party licenses'),
        onTap: () => showLicensePage(context: context, applicationName: 'NOTORYX Connect'),
      )),
      const Card(child: ListTile(
        leading: Icon(Icons.info_outline), title: Text('NOTORYX Connect'),
        subtitle: Text('Development build • Independent mesh companion'))),
      const Card(child: ListTile(
        leading: Icon(Icons.gavel_outlined),
        title: Text('Trademark & compatibility'),
        subtitle: Text(
          'Compatible with Meshtastic® firmware. Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic software components are released under various licenses, see GitHub for details. No warranty is provided - use at your own risk.\n\nNOTORYX Connect is independently developed and is not affiliated with, sponsored by, or endorsed by Meshtastic LLC.',
        ),
      )),
      const _Notice(
        text: 'NOTORYX Connect is an independent project compatible with Meshtastic® firmware. It is not affiliated with, sponsored by, or endorsed by Meshtastic LLC. Do not rely on this development build as a sole method of emergency communication.',
        icon: Icons.shield_outlined),
    ],
  );
}

/// Safe channel editor preview. No channel write is attempted until authenticated
/// admin responses and verified radio readback are implemented.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BastionApp.accentOf(context).withValues(alpha: .4))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: BastionApp.accentOf(context), size: 30),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.primary, letterSpacing: .8)),
        const SizedBox(height: 6),
        Text(detail, style: TextStyle(height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ]),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(value, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900,
        fontSize: 17, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: .6)),
    ]),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 10),
        Expanded(child: Text(text,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(detail, textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
      ]),
    ),
  );
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 80, child: Text(value,
        style: TextStyle(fontWeight: FontWeight.bold,
          color: BastionApp.accentOf(context)))),
      Expanded(child: Text(label)),
    ]),
  );
}

String _rssiLabel(int rssi) {
  if (rssi >= -60) return 'Strong Bluetooth signal';
  if (rssi >= -75) return 'Usable Bluetooth signal';
  if (rssi >= -90) return 'Weak Bluetooth signal';
  return 'Very weak Bluetooth signal';
}


String _connectionLabel(MeshtasticConnectionState state) => switch (state) {
  MeshtasticConnectionState.disconnected => 'OFFLINE',
  MeshtasticConnectionState.discovering => 'SCANNING',
  MeshtasticConnectionState.connecting => 'CONNECTING',
  MeshtasticConnectionState.connected => 'CONNECTED',
  MeshtasticConnectionState.synchronizing => 'SYNCING',
  MeshtasticConnectionState.ready => 'CONNECTED',
  MeshtasticConnectionState.error => 'ERROR',
};

/// Short status words for the dashboard tiles, which are too narrow for
/// CONNECTED or CONNECTING without breaking the word.
String _connectionTileLabel(MeshtasticConnectionState state) => switch (state) {
  MeshtasticConnectionState.disconnected => 'OFFLINE',
  MeshtasticConnectionState.discovering => 'SCANNING',
  MeshtasticConnectionState.connecting => 'LINKING',
  MeshtasticConnectionState.connected => 'ONLINE',
  MeshtasticConnectionState.synchronizing => 'SYNCING',
  MeshtasticConnectionState.ready => 'ONLINE',
  MeshtasticConnectionState.error => 'ERROR',
};

/// Message housekeeping and read-aloud.
class _MessagesCard extends StatelessWidget {
  const _MessagesCard();
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: BastionPreferences.instance,
    builder: (context, _) {
      final p = BastionPreferences.instance;
      return Card(child: ExpansionTile(
        leading: const Icon(Icons.forum_outlined),
        title: const Text('Messages'),
        subtitle: Text([
          p.channelRetentionDays == 0
              ? 'Channel messages kept'
              : 'Channel messages deleted after ${p.channelRetentionDays} day${p.channelRetentionDays == 1 ? '' : 's'}',
          if (p.readAloud) 'read aloud on',
        ].join(' • ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          DropdownButtonFormField<int>(
            initialValue: BastionPreferences.retentionChoices.contains(p.channelRetentionDays)
                ? p.channelRetentionDays : 0,
            decoration: const InputDecoration(
              labelText: 'Delete old channel messages',
              helperText: 'Direct messages are always kept',
            ),
            items: [for (final d in BastionPreferences.retentionChoices)
              DropdownMenuItem(value: d, child: Text(d == 0 ? 'Never' : 'After $d day${d == 1 ? '' : 's'}'))],
            onChanged: (d) => p.update(retentionDays: d),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Read messages aloud'),
            subtitle: const Text('Uses the phone\'s text-to-speech, including with the screen off'),
            value: p.readAloud,
            onChanged: (v) => p.update(speak: v),
          ),
        ],
      ));
    },
  );
}

/// Shows whether Android lets the app keep the radio link open in the
/// background, with a shortcut to the battery optimization setting.
class _BackgroundCard extends StatefulWidget {
  const _BackgroundCard({required this.radio});
  final MeshtasticRadioCoordinator radio;
  @override
  State<_BackgroundCard> createState() => _BackgroundCardState();
}

class _BackgroundCardState extends State<_BackgroundCard> {
  bool? _optimized;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check when the user comes back from Android's settings.
    _lifecycle = AppLifecycleListener(onResume: _check);
    _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final optimized = await BastionForegroundService.batteryOptimized();
    if (mounted) setState(() => _optimized = optimized);
  }

  @override
  Widget build(BuildContext context) {
    final optimized = _optimized;
    if (optimized == null) return const SizedBox.shrink();
    final problem = widget.radio.backgroundProblem;
    return Card(child: ListTile(
      leading: Icon(problem != null || optimized ? Icons.warning_amber : Icons.check_circle_outline,
        color: problem != null || optimized ? Theme.of(context).colorScheme.error : BastionApp.accentOf(context)),
      title: const Text('Background connection'),
      subtitle: Text(problem ?? (optimized
          ? 'Battery optimization can pause NOTORYX Connect when it is not on screen and drop the '
            'radio link. Set its battery use to Unrestricted to stay connected.'
          : 'Allowed to run in the background. A notification shows while a radio is connected.')),
      isThreeLine: true,
      trailing: optimized ? TextButton(
        onPressed: BastionForegroundService.openBatterySettings,
        child: const Text('Open settings')) : null,
    ));
  }
}

class _MapCacheCard extends StatefulWidget {
  const _MapCacheCard();

  @override
  State<_MapCacheCard> createState() => _MapCacheCardState();
}

class _MapCacheCardState extends State<_MapCacheCard> {
  late Future<int?> _size = BastionTileCache.sizeBytes();

  @override
  Widget build(BuildContext context) => Card(child: FutureBuilder<int?>(
    future: _size,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      return ListTile(
        leading: const Icon(Icons.offline_pin_outlined),
        title: const Text('Offline map tiles'),
        subtitle: Text('${bytes == null ? 'Size unknown' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB saved'}'
          '\nMap areas you view online stay available offline for a year (up to 500 MB).'),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: bytes == null || bytes == 0 ? null : () async {
            await BastionTileCache.clear();
            if (mounted) setState(() => _size = BastionTileCache.sizeBytes());
          },
          child: const Text('Clear'),
        ),
      );
    },
  ));
}

class _FieldAlertsCard extends StatelessWidget {
  const _FieldAlertsCard({required this.radio});
  final MeshtasticRadioCoordinator radio;

  Future<void> _update(BuildContext context, BastionAlertSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await radio.setAlertSettings(settings)) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Alert settings apply now, but could not be saved.')));
    }
  }

  static String _duration(Duration d) =>
      d.inHours >= 1 ? '${d.inHours} h' : '${d.inMinutes} min';

  @override
  Widget build(BuildContext context) {
    final s = radio.alertSettings;
    return Card(child: ExpansionTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('Field alerts'),
      subtitle: const Text('Phone notifications only; nothing is sent over the mesh'),
      children: [
        SwitchListTile(
          title: const Text('Low battery'),
          subtitle: Text('Your radio or a favorite reports ${s.batteryThreshold}% or less'),
          value: s.lowBattery,
          onChanged: (v) => _update(context, s.copyWith(lowBattery: v)),
        ),
        ListTile(
          title: const Text('Battery threshold'),
          enabled: s.lowBattery,
          trailing: DropdownButton<int>(
            value: s.batteryThreshold,
            items: [for (final v in BastionAlertSettings.batteryChoices)
              DropdownMenuItem(value: v, child: Text('$v%'))],
            onChanged: s.lowBattery ? (v) => _update(context, s.copyWith(batteryThreshold: v)) : null,
          ),
        ),
        SwitchListTile(
          title: const Text('New node'),
          subtitle: const Text('Your radio hears a node for the first time'),
          value: s.newNode,
          onChanged: (v) => _update(context, s.copyWith(newNode: v)),
        ),
        SwitchListTile(
          title: const Text('Favorite goes quiet'),
          subtitle: Text('A favorite is not heard for ${_duration(s.silence)} while connected'),
          value: s.favoriteSilent,
          onChanged: (v) => _update(context, s.copyWith(favoriteSilent: v)),
        ),
        ListTile(
          title: const Text('Quiet after'),
          enabled: s.favoriteSilent,
          trailing: DropdownButton<Duration>(
            value: s.silence,
            items: [for (final v in BastionAlertSettings.silenceChoices)
              DropdownMenuItem(value: v, child: Text(_duration(v)))],
            onChanged: s.favoriteSilent ? (v) => _update(context, s.copyWith(silence: v)) : null,
          ),
        ),
      ],
    ));
  }
}
