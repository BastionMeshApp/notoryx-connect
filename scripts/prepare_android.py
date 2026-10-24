# Run after flutter create to add BLE permissions and app label.
import re
from pathlib import Path
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
if 'android.permission.BLUETOOTH_SCAN' not in s:
    permissions = '''    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.INTERNET" />
'''
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'+permissions)
s=s.replace('android:label="bastion"', 'android:label="NOTORYX Connect"')
# Foreground service that keeps the BLE link alive in the background.
if 'flutter_foreground_task.service.ForegroundService' not in s:
    service = '''        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="connectedDevice"
            android:stopWithTask="true"
            android:exported="false" />
    </application>'''
    s=s.replace('    </application>', service, 1)
p.write_text(s)

g=Path('android/app/build.gradle.kts')
gradle=g.read_text()

# flutter create derives com.bastionmesh.bastion, which is NOTORYX Core's ID.
gradle, n=re.subn(r'applicationId = "[^"]*"', 'applicationId = "com.bastionmesh.connect"', gradle)
if n != 1:
    raise SystemExit('Could not set applicationId in build.gradle.kts')
g.write_text(gradle)

# flutter_local_notifications needs core library desugaring.
if 'isCoreLibraryDesugaringEnabled' not in gradle:
    gradle=gradle.replace('    compileOptions {\n', '    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n', 1)
    gradle=gradle.replace('\nflutter {', '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n\nflutter {', 1)
    if 'isCoreLibraryDesugaringEnabled' not in gradle or 'desugar_jdk_libs' not in gradle:
        raise SystemExit('Could not enable desugaring in build.gradle.kts')
    g.write_text(gradle)

# Keep the launcher icon used for notifications through R8 resource shrinking.
keep=Path('android/app/src/main/res/raw/keep.xml')
keep.parent.mkdir(parents=True, exist_ok=True)
keep.write_text('<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources xmlns:tools="http://schemas.android.com/tools"\n'
    '    tools:keep="@mipmap/ic_launcher" />\n')
print('Prepared Android manifest and Gradle')

# Keep one Flutter engine for the whole process instead of one per activity.
# The Bluetooth link lives in the engine, and FlutterActivity destroys its
# engine when the activity is destroyed (Back on the home screen, or Android
# reclaiming a backgrounded activity), which closed the radio connection even
# though the foreground service kept the process alive.
activity=Path('android/app/src/main/kotlin/com/bastionmesh/bastion/MainActivity.kt')
if not activity.exists():
    raise SystemExit(f'{activity} not found; was flutter create run with --org com.bastionmesh --project-name bastion?')
activity.write_text("""package com.bastionmesh.bastion

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class MainActivity : FlutterActivity() {
    // A new activity reattaches to the running engine, so the radio link and
    // app state survive the activity being destroyed.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        return cache.get(ENGINE_ID) ?: FlutterEngine(context.applicationContext).also {
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ENGINE_ID, it)
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private companion object {
        const val ENGINE_ID = "notoryx"
    }
}
""")
print('Kept one Flutter engine across activities')
