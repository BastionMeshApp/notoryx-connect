import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Closes the app after a restore or delete, so nothing still in memory is
/// saved over the new data. `SystemNavigator.pop` is ignored on desktop.
Future<void> closeApp() async {
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) exit(0);
  await SystemNavigator.pop();
}
