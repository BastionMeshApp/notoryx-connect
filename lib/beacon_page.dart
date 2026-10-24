import 'dart:convert';

import 'package:flutter/material.dart';

import 'channel_share_page.dart';
import 'services/bastion_beacons.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Mesh Beacons: invitations heard on the mesh, and sending one by hand.
class BeaconPage extends StatefulWidget {
  const BeaconPage({super.key, required this.radio});
  final MeshtasticRadioCoordinator radio;
  @override
  State<BeaconPage> createState() => _BeaconPageState();
}

class _BeaconPageState extends State<BeaconPage> {
  final _message = TextEditingController();
  bool _offerChannel = false;
  bool _sending = false;
  String? _status;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  int get _bytes => utf8.encode(_message.text).length;

  Future<void> _send() async {
    final offer = _offerChannel;
    if (offer) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share your primary channel?'),
          content: const Text('The beacon will include your primary channel\'s name and key. '
              'Anyone in range can then join it and read its messages.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Share')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _sending = true;
      _status = null;
    });
    try {
      await widget.radio.sendBeacon(_message.text, offerPrimaryChannel: offer);
      if (!mounted) return;
      setState(() => _status = 'Beacon sent.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = switch (error) {
        ArgumentError(:final message) => '$message',
        StateError(:final message) => message,
        _ => 'Beacon not sent: $error',
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mesh beacons'), actions: [
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) => IconButton(
          tooltip: 'Clear heard beacons',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: widget.radio.beacons.isEmpty ? null : widget.radio.clearBeacons,
        ),
      ),
    ]),
    body: SafeArea(top: false, child: AnimatedBuilder(
      animation: widget.radio,
      builder: (context, _) {
        final radio = widget.radio;
        final next = radio.nextBeaconAllowed;
        final canSend = radio.isReady && next == null && !_sending &&
            _message.text.trim().isNotEmpty && _bytes <= BastionBeaconLog.maxMessageBytes;
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('A beacon is a short broadcast that tells nearby radios a mesh is here, '
              'and can invite them to a channel. Radios on the newer Meshtastic firmware show it; '
              'NOTORYX Connect shows beacons it hears with any firmware.'),
          const SizedBox(height: 16),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('SEND A BEACON', style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Beacon message',
                  helperText: 'Sent on your primary channel. At most one beacon an hour.',
                  helperMaxLines: 2,
                  counterText: '$_bytes/${BastionBeaconLog.maxMessageBytes} bytes',
                  errorText: _bytes > BastionBeaconLog.maxMessageBytes ? 'Too long' : null,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Invite to my primary channel'),
                subtitle: const Text('Includes the channel name and key, and your region and preset'),
                value: _offerChannel,
                onChanged: (value) => setState(() => _offerChannel = value),
              ),
              FilledButton.icon(
                onPressed: canSend ? _send : null,
                icon: const Icon(Icons.campaign_outlined),
                label: Text(_sending ? 'Sending…' : 'Send beacon'),
              ),
              if (!radio.isReady)
                const Padding(padding: EdgeInsets.only(top: 8),
                  child: Text('Connect to a radio to send a beacon.'))
              else if (next != null)
                Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text('Next beacon can be sent at ${_time(next)}.')),
              if (_status != null)
                Semantics(liveRegion: true, child: Padding(
                  padding: const EdgeInsets.only(top: 8), child: Text(_status!))),
            ]),
          )),
          const SizedBox(height: 8),
          Text('HEARD BEACONS', style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (radio.beacons.isEmpty)
            const Card(child: ListTile(
              leading: Icon(Icons.wifi_tethering_off),
              title: Text('No beacons heard yet'),
              subtitle: Text('Beacons from radios in range on your channels appear here.'),
            )),
          for (final beacon in radio.beacons) _BeaconCard(radio: radio, beacon: beacon),
        ]);
      },
    )),
  );
}

class _BeaconCard extends StatelessWidget {
  const _BeaconCard({required this.radio, required this.beacon});
  final MeshtasticRadioCoordinator radio;
  final HeardBeacon beacon;

  @override
  Widget build(BuildContext context) {
    final details = [
      'From ${radio.nodeName(beacon.from)}',
      'heard ${_time(beacon.heardAt)}',
      if (beacon.snr != null) 'SNR ${beacon.snr!.toStringAsFixed(1)} dB',
      if (beacon.rssi != null) 'RSSI ${beacon.rssi} dBm',
    ].join(' • ');
    final offer = [
      if (beacon.offerChannel != null)
        'Channel "${beacon.offerChannel!.name.isEmpty ? 'Default' : beacon.offerChannel!.name}"',
      if (beacon.offerRegion != null) 'region ${beacon.offerRegion!.name}',
      if (beacon.offerPreset != null) 'preset ${beacon.offerPreset!.name}',
      if (beacon.offerFrequencySlot != null) 'slot ${beacon.offerFrequencySlot}',
    ].join(', ');
    final link = beacon.joinLink;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(beacon.message.isEmpty ? '(no message)' : beacon.message,
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(details, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (offer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Invites to: $offer'),
        ],
        if (link != null) ...[
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Review and join channel'),
            onPressed: radio.isReady ? () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ChannelImportPage(radio: radio, initialLink: link))) : null,
          )),
        ],
      ]),
    ));
  }
}

String _time(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay
      ? '${two(local.hour)}:${two(local.minute)}'
      : '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
