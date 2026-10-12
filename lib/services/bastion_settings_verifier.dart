import 'package:protobuf/protobuf.dart';

/// Verifies the fields deliberately changed, including omitted protobuf defaults.
abstract final class BastionSettingsVerifier {
  static bool equivalent(Object? a, Object? b) {
    if (a is GeneratedMessage || b is GeneratedMessage) {
      final model = a is GeneratedMessage ? a : b as GeneratedMessage;
      if (a != null && a is! GeneratedMessage || b != null && b is! GeneratedMessage) return false;
      final left = a as GeneratedMessage? ?? model.createEmptyInstance();
      final right = b as GeneratedMessage? ?? model.createEmptyInstance();
      if (left.runtimeType != right.runtimeType) return false;
      return left.info_.sortedByTag.every((f) => equivalent(left.getField(f.tagNumber), right.getField(f.tagNumber)));
    }
    if (a is List && b is List) {
      return a.length == b.length && List.generate(a.length, (i) => i).every((i) => equivalent(a[i], b[i]));
    }
    if (a is Map && b is Map) {
      return a.length == b.length && a.keys.every((k) => b.containsKey(k) && equivalent(a[k], b[k]));
    }
    return a == b;
  }

  static bool matchesChanges(GeneratedMessage original, GeneratedMessage requested, GeneratedMessage observed) {
    if (original.runtimeType != requested.runtimeType || observed.runtimeType != requested.runtimeType) return false;
    for (final f in requested.info_.sortedByTag) {
      final before = original.getField(f.tagNumber);
      final wanted = requested.getField(f.tagNumber);
      final actual = observed.getField(f.tagNumber);
      if (equivalent(before, wanted)) continue;
      if (wanted is GeneratedMessage) {
        if (before != null && before is! GeneratedMessage || actual != null && actual is! GeneratedMessage) return false;
        if (!matchesChanges(before as GeneratedMessage? ?? wanted.createEmptyInstance(), wanted,
            actual as GeneratedMessage? ?? wanted.createEmptyInstance())) return false;
      } else if (!equivalent(wanted, actual)) { return false; }
    }
    return true;
  }

  /// Writes once, waits for the same radio and performs a new admin read.
  static Future<T> save<T extends GeneratedMessage>({
    required int node,
    required int? Function() currentNode,
    required T original,
    required T requested,
    required Future<void> Function() write,
    required Future<void> Function(int node) waitForRadio,
    required Future<T> Function() read,
  }) async {
    void checkIdentity() {
      if (currentNode() != node) throw StateError('Connected radio changed. Reload settings before continuing.');
    }
    checkIdentity();
    await write();
    await waitForRadio(node);
    checkIdentity();
    final observed = await read();
    checkIdentity();
    if (!matchesChanges(original, requested, observed)) {
      throw StateError('Radio acknowledged the write, but the requested changes were not confirmed by a fresh read. Reload before changing anything else.');
    }
    return observed;
  }
}
