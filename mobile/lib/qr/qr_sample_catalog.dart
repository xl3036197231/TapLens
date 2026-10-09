import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'qr_sample_index.g.dart';

class QrFixedSample {
  final String sampleId;
  final String catalogSchemaVersion;
  final String catalogRevision;
  final String manifestSchemaVersion;
  final String payloadSha256;
  final String analyzerProfile;

  const QrFixedSample({
    required this.sampleId,
    required this.catalogSchemaVersion,
    required this.catalogRevision,
    required this.manifestSchemaVersion,
    required this.payloadSha256,
    required this.analyzerProfile,
  });

  Map<String, String> toJson() => {
        'sample_id': sampleId,
        'catalog_schema_version': catalogSchemaVersion,
        'catalog_revision': catalogRevision,
        'manifest_schema_version': manifestSchemaVersion,
        'payload_sha256': payloadSha256,
      };

  static QrFixedSample? matchRawDecodedText(String rawDecodedText) {
    // Hash the scanner's exact text. Deliberately do not trim or normalize it.
    final digest = sha256.convert(utf8.encode(rawDecodedText)).toString();
    final value = qrFixedSampleIndex[digest];
    if (value == null) return null;
    return QrFixedSample(
      sampleId: value['sample_id']!,
      catalogSchemaVersion: value['catalog_schema_version']!,
      catalogRevision: value['catalog_revision']!,
      manifestSchemaVersion: value['manifest_schema_version']!,
      payloadSha256: value['payload_sha256']!,
      analyzerProfile: value['analyzer_profile']!,
    );
  }
}
