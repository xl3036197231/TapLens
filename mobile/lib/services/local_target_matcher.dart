import 'dart:convert';

/// Confirms that a fresh local parse still describes the same input target.
class LocalTargetMatcher {
  static bool matches(Map<String, dynamic> previous, Object? candidate) {
    if (candidate is! Map) return false;
    final current = Map<String, dynamic>.from(candidate);
    const exactKeys = [
      'input_type',
      'display_value',
      'scheme',
      'host',
      'path',
      'package_name',
      'expected_package_name',
      'fallback_url',
    ];
    if (exactKeys.any((key) => previous[key] != current[key])) return false;
    for (final key in ['parameters', 'extras']) {
      final oldValue = previous[key];
      final newValue = current[key];
      if (oldValue is! Map || newValue is! Map) return false;
      final oldKeys = oldValue.keys.map((item) => item.toString()).toSet();
      final newKeys = newValue.keys.map((item) => item.toString()).toSet();
      if (oldKeys.length != newKeys.length ||
          !oldKeys.containsAll(newKeys) ||
          oldKeys.any(
            (item) => jsonEncode(oldValue[item]) != jsonEncode(newValue[item]),
          )) {
        return false;
      }
    }
    return true;
  }
}
