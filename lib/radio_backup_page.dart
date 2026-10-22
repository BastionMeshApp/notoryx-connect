import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/bastion_encrypted_backup.dart';
import 'services/bastion_radio_backup.dart';
import 'services/meshtastic_radio_coordinator.dart';

Future<String> _encryptBackup((String, String) input) =>
    BastionEncryptedBackup().encrypt(input.$1, input.$2);
Future<String> _decryptBackup((String, String) input) =>
    BastionEncryptedBackup().decrypt(input.$1, input.$2);

/// Explicit export/import of encrypted settings; passwords are never persisted.
class RadioBackupPage extends StatefulWidget {
  const RadioBackupPage({super.key, required this.radio});
  final MeshtasticRadioCoordinator radio;
  @override
  State<RadioBackupPage> createState() => _RadioBackupPageState();
}

class _RadioBackupPageState extends State<RadioBackupPage> {
  final _password = TextEditingController();
  final _encrypted = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _encrypted.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _status = null; });
    try { await action(); }
    on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = 'Operation failed. If a restore had started, '
          'settings may be partially changed. Reconnect and check the radio before retrying.');
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _backup() => _run(() async {
    final password = _password.text;
    if (password.length < 12) throw const FormatException('Use at least 12 characters for the backup password.');
    final snapshot = await BastionRadioBackup(widget.radio).capture();
    final plain = await snapshot.encode();
    final encrypted = await compute(_encryptBackup, (plain, password));
    if (!mounted) return;
    _encrypted.text = encrypted;
    setState(() => _status = 'Encrypted backup ready. Copy it and save it in a text file. '
        'Keep the password separately; it cannot be recovered.');
  });

  Future<void> _restore() => _run(() async {
    final password = _password.text;
    final encrypted = _encrypted.text;
    final plain = await compute(_decryptBackup, (encrypted, password));
    final snapshot = await RadioBackupSnapshot.decode(plain);
    if (!mounted) return;
    final target = widget.radio.backupNodeNum;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Replace radio settings?'),
      content: Text('Backup from radio !${snapshot.nodeNum.toRadixString(16)} '
          '(firmware ${snapshot.firmware}), created ${snapshot.createdAt.toLocal()}.\n\n'
          'Target: !${target.toRadixString(16)}. Replaces owner names, all 8 channel slots '
          'including their secret keys, ${snapshot.configs.length} configuration sections '
          'and ${snapshot.modules.length} modules. Device identity/security keys, '
          'session credentials, phone chats and maps are not restored (use Phone data backup for those).\n\n'
          'Save a backup of the target first. The radio may reboot or lose mesh connectivity. '
          'A radio write cannot guarantee rollback after a power or connection failure.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace settings'))],
    ));
    if (confirmed != true || !mounted) return;
    if (widget.radio.backupNodeNum != target) throw StateError('Connected radio changed.');
    await BastionRadioBackup(widget.radio).restore(snapshot);
    if (mounted) setState(() => _status = 'Restore complete. Fresh radio readback matches the backup.');
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
    appBar: AppBar(title: const Text('Encrypted radio backup')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Backs up fresh radio configuration and modules reported by the firmware, '
          'all channel slots and owner names. Channel keys and any network/module credentials '
          'are password encrypted. Device identity keys and session credentials are excluded.'),
      const SizedBox(height: 16),
      TextField(controller: _password, obscureText: true, enableSuggestions: false,
          autocorrect: false, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Backup password (at least 12 characters)',
              border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _busy ? null : _backup,
          icon: const Icon(Icons.lock), label: const Text('Create encrypted backup')),
      const SizedBox(height: 16),
      TextField(controller: _encrypted, maxLines: 5, enabled: !_busy,
          enableSuggestions: false, autocorrect: false,
          decoration: const InputDecoration(labelText: 'Encrypted backup text',
              hintText: 'Paste a saved encrypted backup to restore', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _busy ? null : () async {
        if (_encrypted.text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: _encrypted.text));
        if (mounted) setState(() => _status = 'Encrypted backup copied. Save it in a text file.');
      }, icon: const Icon(Icons.copy), label: const Text('Copy encrypted backup')),
      OutlinedButton.icon(onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.settings_backup_restore), label: const Text('Review and restore')),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_status != null) Padding(padding: const EdgeInsets.all(16), child: Text(_status!)),
    ]),
  ));
}
