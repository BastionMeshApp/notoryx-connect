import 'package:flutter/material.dart';

import 'services/bastion_trip.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Plan your trip: who gets check-ins and SOS, and when to warn.
class TripPage extends StatefulWidget {
  const TripPage({super.key, required this.radio});
  final MeshtasticRadioCoordinator radio;
  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.radio.trip.plan.name);
  String? _status;

  BastionTripController get _trip => widget.radio.trip;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _update(TripPlan plan) async {
    try {
      await _trip.updatePlan(plan);
      if (mounted) setState(() => _status = null);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _status = '${e.message}');
    }
  }

  /// Trip contact candidates: nodes heard now plus saved favorites.
  List<({int num, String name})> _candidates() {
    final me = widget.radio.localNodeNum;
    final seen = <int>{};
    final result = <({int num, String name})>[];
    for (final num in [
      ..._trip.plan.members,
      for (final r in widget.radio.nodeDex) if (r.favorite) r.num,
      for (final n in widget.radio.nodes) n.num,
    ]) {
      if (num == me || !seen.add(num)) continue;
      result.add((num: num, name: widget.radio.nodeName(num)));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan your trip')),
    body: SafeArea(top: false, child: AnimatedBuilder(
      animation: widget.radio,
      builder: (context, _) {
        final plan = _trip.plan;
        final channels = widget.radio.channelMetadata.where((c) => c.role != 0).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Trip name'),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (value) => _update(plan.copyWith(name: value.trim().isEmpty ? 'My trip' : value.trim())),
            onTapOutside: (_) {
              final value = _name.text.trim();
              if (value.isNotEmpty && value != plan.name) _update(plan.copyWith(name: value));
            },
          ),
          const SizedBox(height: 16),
          Text('TRIP CONTACTS (${plan.members.length}/${TripPlan.maxMembers})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const Text('Check-ins and SOS go to each of them as a direct message.'),
          const SizedBox(height: 8),
          if (_candidates().isEmpty)
            const Card(child: ListTile(
              leading: Icon(Icons.person_search),
              title: Text('No nodes yet'),
              subtitle: Text('Connect to your radio so nearby nodes and favorites appear here.'),
            )),
          for (final c in _candidates())
            CheckboxListTile(
              title: Text(c.name),
              subtitle: Text('!${c.num.toRadixString(16).padLeft(8, '0')}'),
              value: plan.members.contains(c.num),
              onChanged: (on) => _update(plan.copyWith(members: on == true
                  ? [...plan.members, c.num]
                  : plan.members.where((m) => m != c.num).toList())),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: overdueChoices.contains(plan.overdueMinutes) ? plan.overdueMinutes : 60,
            decoration: const InputDecoration(
              labelText: 'Overdue alert',
              helperText: 'Warns you when a trip contact has not been heard for this long',
              helperMaxLines: 2,
            ),
            items: [for (final m in overdueChoices)
              DropdownMenuItem(value: m, child: Text(m == 0 ? 'Off' : _minutes(m)))],
            onChanged: (m) => _update(plan.copyWith(overdueMinutes: m)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: reminderChoices.contains(plan.reminderMinutes) ? plan.reminderMinutes : 0,
            decoration: const InputDecoration(
              labelText: 'Check-in reminder',
              helperText: 'Reminds you to check in this long after your last check-in',
              helperMaxLines: 2,
            ),
            items: [for (final m in reminderChoices)
              DropdownMenuItem(value: m, child: Text(m == 0 ? 'Off' : 'Every ${_minutes(m)}'))],
            onChanged: (m) => _update(plan.copyWith(reminderMinutes: m)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: plan.sosChannel >= 0 && channels.any((c) => c.index == plan.sosChannel)
                ? plan.sosChannel : -1,
            decoration: const InputDecoration(
              labelText: 'Also send SOS on a channel',
              helperText: 'Everyone on that channel sees your SOS, not just trip contacts',
              helperMaxLines: 2,
            ),
            items: [
              const DropdownMenuItem(value: -1, child: Text('No, trip contacts only')),
              for (final c in channels)
                DropdownMenuItem(value: c.index,
                  child: Text('Channel ${c.index} • ${c.name.isEmpty ? 'Default' : c.name}')),
            ],
            onChanged: (i) => _update(plan.copyWith(sosChannel: i)),
          ),
          const SizedBox(height: 20),
          if (plan.active)
            OutlinedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End trip'),
              onPressed: _trip.stopTrip,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.hiking),
              label: const Text('Start trip'),
              onPressed: plan.members.isEmpty ? null : _trip.startTrip,
            ),
          const SizedBox(height: 8),
          Text(plan.active
              ? 'Trip running since ${_time(plan.startedAt!)}. Overdue alerts and reminders are on.'
              : 'Starting the trip turns on overdue alerts and check-in reminders. '
                'Check-ins and SOS work any time.'),
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
        ]);
      },
    )),
  );
}

String _minutes(int m) => m < 60 ? '$m min' : '${m ~/ 60} h';

String _time(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
