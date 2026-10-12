import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/bastion_bot_guard.dart';
import 'services/bastion_field_log.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Local incident records, deliberate template sends and receiver coverage history.
class FieldToolsPage extends StatefulWidget {
  const FieldToolsPage({super.key, required this.radio});
  final MeshtasticRadioCoordinator radio;
  @override
  State<FieldToolsPage> createState() => _FieldToolsPageState();
}

class _FieldToolsPageState extends State<FieldToolsPage> {
  final note = TextEditingController();
  final message = TextEditingController(text: 'ASSISTANCE REQUESTED | Name: | Location: | Need:');
  int channel = 0;
  bool busy = false;
  String? status;
  static const templates = {
    'Assistance': 'ASSISTANCE REQUESTED | Name: | Location: | Need:',
    'Check-in': 'CHECK-IN | Name: | Location: | Status:',
    'All clear': 'ALL CLEAR | Name: | Location: | Details:',
  };

  @override
  void dispose() { note.dispose(); message.dispose(); super.dispose(); }

  Future<void> action(Future<void> Function() operation, String success) async {
    setState(() { busy = true; status = null; });
    try { await operation(); if (mounted) setState(() => status = success); }
    catch (error) { if (mounted) setState(() => status = '$error'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> send() async {
    final text = message.text.trim();
    if (text.isEmpty || utf8.encode(text).length > 220) {
      setState(() => status = 'Enter a message of 1–220 UTF-8 bytes.'); return;
    }
    final node = widget.radio.localNodeNum;
    final selected = channel;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Broadcast to channel $selected?'),
      content: SingleChildScrollView(child: Text('$text\n\nSending does not prove reception. Confirm with a reply or voice contact.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send message'))],
    ));
    if (!mounted || confirmed != true) return;
    await action(() async {
      if (!widget.radio.isReady || widget.radio.localNodeNum != node ||
          !widget.radio.channelMetadata.any((c) => c.index == selected && c.role != 0)) {
        throw StateError('Radio or channel changed. Reconnect and review the message.');
      }
      await widget.radio.sendText(text: text, channel: selected);
    }, 'Submitted to the radio. Check Chats for transmission status and replies.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field records')),
    body: SafeArea(top: false, child: AnimatedBuilder(
      animation: Listenable.merge([widget.radio, BastionFieldLog.instance, BastionBotGuard.instance]),
      builder: (context, _) {
        final log = BastionFieldLog.instance;
        final guard = BastionBotGuard.instance;
        final channels = widget.radio.channelMetadata.where((c) => c.role != 0).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (status != null) Padding(padding: const EdgeInsets.all(8), child: Text(status!, semanticsLabel: status)),
          if (log.error != null) ListTile(leading: const Icon(Icons.error_outline), title: Text(log.error!)),
          Card(child: ExpansionTile(initiallyExpanded: true,
            title: const Text('Incident log'), subtitle: const Text('Private notes saved on this phone'), childrenPadding: const EdgeInsets.all(16), children: [
              TextField(controller: note, maxLength: 1000, minLines: 2, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Incident or observation')),
              FilledButton(onPressed: busy ? null : () => action(() async {
                await log.addIncident(note.text, radio: widget.radio.localNodeNum); note.clear();
              }, 'Incident saved.'), child: const Text('Save incident')),
              TextButton(onPressed: () => action(() => Clipboard.setData(ClipboardData(text: log.exportCsv('incident'))),
                'Incident CSV copied. Paste into a file or spreadsheet.'), child: const Text('Copy incident CSV')),
              for (final r in log.records.where((r) => r['kind'] == 'incident').toList().reversed)
                ListTile(title: Text(r['note']! as String), subtitle: Text('${r['time']} • Radio ${r['radio'] ?? 'unassigned'}')),
            ])),
          Card(child: ExpansionTile(title: const Text('Emergency & check-in templates'),
            subtitle: const Text('Edit details, choose a channel, then review before sending'),
            childrenPadding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 8, children: [for (final t in templates.entries)
                OutlinedButton(onPressed: () => setState(() => message.text = t.value), child: Text(t.key))]),
              TextField(controller: message, minLines: 3, maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message — replace the blank details')),
              DropdownButtonFormField<int>(initialValue: channels.any((c) => c.index == channel) ? channel : null,
                decoration: const InputDecoration(labelText: 'Broadcast channel'),
                items: [for (final c in channels) DropdownMenuItem(value: c.index, child: Text('Channel ${c.index} • ${c.name}'))],
                onChanged: (v) { if (v != null) setState(() => channel = v); }),
              const SizedBox(height: 12),
              FilledButton(onPressed: busy || !widget.radio.isReady || channels.isEmpty ? null : send,
                child: const Text('Review message')),
              const Text('A template is ordinary mesh text. It does not contact emergency services.'),
            ])),
          Card(child: ExpansionTile(title: const Text('Coverage history'),
            subtitle: const Text('Receiver location with received RF signal • local recording only'),
            childrenPadding: const EdgeInsets.all(16), children: [
              SwitchListTile(title: const Text('Record coverage'),
                subtitle: const Text('Requests phone GPS. Stops on disconnect. Does not send your location.'),
                value: widget.radio.recordingCoverage,
                onChanged: busy || (!widget.radio.isReady && !widget.radio.recordingCoverage) ? null
                  : (v) => action(() => widget.radio.setCoverageRecording(v), v ? 'Coverage recorder enabled; waiting for a fresh accurate GPS fix and RF packets.' : 'Coverage recorder stopped.')),
              if (widget.radio.coverageProblem != null) Text(widget.radio.coverageProblem!),
              Text('${log.records.where((r) => r['kind'] == 'coverage').length} readings • maximum 2000 total records • coverage expires after 30 days'),
              TextButton(onPressed: () => action(() => Clipboard.setData(ClipboardData(text: log.exportCsv('coverage'))),
                'Coverage CSV copied. Paste into a file or spreadsheet.'), child: const Text('Copy coverage CSV')),
              for (final r in log.records.where((r) => r['kind'] == 'coverage').toList().reversed.take(50))
                ListTile(title: Text('Node ${r['from']} • SNR ${r['snr'] ?? '—'} • RSSI ${r['rssi'] ?? '—'}'),
                  subtitle: Text('${r['time']}\nReceiver ${r['lat']}, ${r['lon']} • Radio ${r['radio']}')),
            ])),
          Card(child: ExpansionTile(title: const Text('Bot safeguards & quiet hours'),
            subtitle: const Text('6 replies/hour • 30-second spacing • 5-minute per-node cooldown'),
            children: [
              const ListTile(title: Text('Enable Bot Mode in Chats for this session.'),
                subtitle: Text('Only fresh messages on the selected channel qualify. Replay and Bastion replies are ignored. Quiet hours use this phone’s local time.')),
              SwitchListTile(title: const Text('Quiet hours'), value: guard.quietEnabled,
                onChanged: (v) => guard.update(quiet: v)),
              for (final isStart in [true, false]) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<int>(initialValue: isStart ? guard.quietStart : guard.quietEnd,
                  decoration: InputDecoration(labelText: isStart ? 'Quiet hours start' : 'Quiet hours end'),
                  items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                  onChanged: (v) { if (v != null) { guard.update(start: isStart ? v : null, end: isStart ? null : v); } })),
              Padding(padding: const EdgeInsets.all(16), child: DropdownButtonFormField<int>(initialValue: guard.channel,
                decoration: const InputDecoration(labelText: 'Bot channel slot'),
                items: [for (var i = 0; i < 8; i++) DropdownMenuItem(value: i, child: Text('Channel $i'))],
                onChanged: (v) { if (v != null) { guard.update(selectedChannel: v); } })),
              if (guard.error != null) ListTile(title: Text(guard.error!)),
            ])),
        ]);
      },
    )),
  );
}
