import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process, and with it the BLE link, alive in the background.
///
/// Android kills or throttles background apps; a foreground service with a
/// visible notification prevents that while a radio is connected. The BLE
/// work itself stays in the main isolate, so the task handler does nothing.
abstract interface class BastionBackgroundKeeper {
  /// Starts or updates the notification for [radioName].
  Future<void> keepAlive({required String radioName, required bool reconnecting});

  Future<void> release();
}

class BastionForegroundService implements BastionBackgroundKeeper {
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Why the background service could not start, for the user; null when it
  /// started or was never needed.
  final ValueNotifier<String?> problem = ValueNotifier(null);

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Whether Android battery optimization may pause the app in the
  /// background; null where that does not apply.
  static Future<bool?> batteryOptimized() async {
    if (!_supported) return null;
    try {
      return !await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return null;
    }
  }

  /// Opens Android's battery optimization settings.
  static Future<void> openBatterySettings() async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (error) {
      debugPrint('Bastion battery settings error: $error');
    }
  }

  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async {
    if (!_supported) return;
    final title = reconnecting ? 'Reconnecting to $radioName…' : 'Connected to $radioName';
    const text = 'NOTORYX Connect keeps the radio link open in the background.';
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
        problem.value = null;
        return;
      }
      _initialize();
      if (!_permissionRequested) {
        _permissionRequested = true;
        // Android 13+: without this the service still runs but its
        // notification is hidden.
        if (await FlutterForegroundTask.checkNotificationPermission() !=
            NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: 4242,
        serviceTypes: const [ForegroundServiceTypes.connectedDevice],
        notificationTitle: title,
        notificationText: text,
        callback: _startCallback,
      );
      if (result case ServiceRequestFailure(:final error)) {
        debugPrint('Bastion background service did not start: $error');
        problem.value = _unavailable(error);
      } else {
        problem.value = null;
      }
    } catch (error) {
      // Background keep-alive is best effort; the foreground link still works.
      debugPrint('Bastion background service error: $error');
      problem.value = _unavailable(error);
    }
  }

  static String _unavailable(Object error) =>
      'The background connection service could not start ($error), so Android '
      'may drop the radio link when NOTORYX Connect is not on screen.';

  @override
  Future<void> release() async {
    if (!_supported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (error) {
      debugPrint('Bastion background service stop error: $error');
    }
  }

  void _initialize() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bastion_radio_link',
        channelName: 'Radio connection',
        channelDescription: 'Shown while NOTORYX Connect keeps a radio connected.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // A restarted service would have no BLE session behind it.
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() => FlutterForegroundTask.setTaskHandler(_IdleTaskHandler());

class _IdleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
