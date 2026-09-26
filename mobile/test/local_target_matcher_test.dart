import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/services/local_target_matcher.dart';

Map<String, dynamic> _target() => {
      'input_type': 'url',
      'display_value': 'https://campus.example.test/go?source=poster',
      'scheme': 'https',
      'host': 'campus.example.test',
      'path': '/go',
      'package_name': null,
      'expected_package_name': null,
      'fallback_url': null,
      'parameters': <String, List<String>>{
        'source': ['poster'],
      },
      'extras': <String, String>{},
    };

void main() {
  test('same parsed URL and parameters are accepted', () {
    expect(LocalTargetMatcher.matches(_target(), _target()), isTrue);
  });

  test('different URL paths and parameter values are rejected', () {
    final changedPath = _target()..['path'] = '/different';
    expect(LocalTargetMatcher.matches(_target(), changedPath), isFalse);

    final changedParameter = _target()
      ..['parameters'] = <String, List<String>>{
        'source': ['email'],
      };
    expect(LocalTargetMatcher.matches(_target(), changedParameter), isFalse);
  });

  test('different parameter or intent-extra names are rejected', () {
    final changedParameters = _target()
      ..['parameters'] = <String, List<String>>{
        'campaign': ['poster'],
      };
    expect(LocalTargetMatcher.matches(_target(), changedParameters), isFalse);

    final changedExtras = _target()
      ..['extras'] = <String, String>{'student_id': '[REDACTED]'};
    expect(LocalTargetMatcher.matches(_target(), changedExtras), isFalse);
  });
}
