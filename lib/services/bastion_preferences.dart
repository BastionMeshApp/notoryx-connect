import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone appearance preferences; radio configuration is never changed.
class BastionPreferences extends ChangeNotifier {
  static final instance = BastionPreferences();
  ThemeMode theme = ThemeMode.dark;
  bool statistics = true;
  bool meshHealth = true;
  bool encounters = true;
  String? error;

  Future<void> load() async {
    try {
      final p = SharedPreferencesAsync();
      final name = await p.getString('bastion.theme');
      theme = ThemeMode.values.where((v) => v.name == name).firstOrNull ?? ThemeMode.dark;
      statistics = await p.getBool('bastion.dashboard.statistics') ?? true;
      meshHealth = await p.getBool('bastion.dashboard.health') ?? true;
      encounters = await p.getBool('bastion.dashboard.encounters') ?? true;
    } catch (_) { error = 'Appearance preferences could not be loaded.'; }
    notifyListeners();
  }

  Future<void> update({ThemeMode? mode, bool? stats, bool? health, bool? saved}) async {
    theme = mode ?? theme;
    statistics = stats ?? statistics;
    meshHealth = health ?? meshHealth;
    encounters = saved ?? encounters;
    error = null;
    notifyListeners();
    try {
      final p = SharedPreferencesAsync();
      await p.setString('bastion.theme', theme.name);
      await p.setBool('bastion.dashboard.statistics', statistics);
      await p.setBool('bastion.dashboard.health', meshHealth);
      await p.setBool('bastion.dashboard.encounters', encounters);
    } catch (_) { error = 'Changes apply now, but could not be saved.'; notifyListeners(); }
  }
}

class BastionAppearanceCard extends StatelessWidget {
  const BastionAppearanceCard({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: BastionPreferences.instance,
    builder: (context, _) {
      final p = BastionPreferences.instance;
      return Card(child: ExpansionTile(
        title: const Text('Appearance & dashboard'),
        leading: const Icon(Icons.palette_outlined),
        children: [
          for (final mode in ThemeMode.values)
            ListTile(title: Text('${mode.name[0].toUpperCase()}${mode.name.substring(1)} theme'),
              trailing: p.theme == mode ? const Icon(Icons.check) : null,
              onTap: () => p.update(mode: mode)),
          SwitchListTile(title: const Text('Dashboard statistics'), value: p.statistics,
            onChanged: (v) => p.update(stats: v)),
          SwitchListTile(title: const Text('Mesh health & signal'), value: p.meshHealth,
            onChanged: (v) => p.update(health: v)),
          SwitchListTile(title: const Text('Saved encounters'), value: p.encounters,
            onChanged: (v) => p.update(saved: v)),
          if (p.error != null) ListTile(title: Text(p.error!)),
        ],
      ));
    },
  );
}
