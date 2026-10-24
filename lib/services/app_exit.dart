import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Closes the app after a restore or delete, so nothing still in memory is
/// saved over the new data. On Android the process is ended too: the engine
/// outlives the activity (see `scripts/prepare_android.py`), so closing the
/// screen alone would keep the old state running.
Future<void> closeApp() async {
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux || Platform.isAndroid)) {
    exit(0);
  }
  await SystemNavigator.pop();
}
