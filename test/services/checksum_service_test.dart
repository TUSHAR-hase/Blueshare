import 'dart:io';
import 'dart:typed_data';

import 'package:blueshare/data/services/checksum_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChecksumService', () {
    test('creates stable SHA-256 checksum for bytes', () {
      final checksumService = ChecksumService();
      final bytes = Uint8List.fromList('BlueShare'.codeUnits);

      expect(
        checksumService.sha256Bytes(bytes),
        '09e3362d086aa8fbb034a7b9600c7e364cd9d5d46fcc78b3fd5698eb6262f733',
      );
    });

    test('matches file checksum with in-memory checksum', () async {
      final checksumService = ChecksumService();
      final tempDir = await Directory.systemTemp.createTemp(
        'blueshare_checksum',
      );
      final file = File('${tempDir.path}/sample.txt');
      final content = Uint8List.fromList('Transfer integrity'.codeUnits);
      await file.writeAsBytes(content);

      final fromBytes = checksumService.sha256Bytes(content);
      final fromFile = await checksumService.sha256File(file.path);

      expect(fromFile, fromBytes);

      await tempDir.delete(recursive: true);
    });
  });
}
