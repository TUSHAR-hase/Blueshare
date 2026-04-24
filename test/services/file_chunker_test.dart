import 'dart:io';
import 'dart:typed_data';

import 'package:blueshare/data/services/file_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileChunker', () {
    test('calculates total chunks correctly', () {
      const chunker = FileChunker();

      expect(chunker.totalChunksFor(totalBytes: 0, chunkSize: 1024), 0);
      expect(chunker.totalChunksFor(totalBytes: 1, chunkSize: 1024), 1);
      expect(chunker.totalChunksFor(totalBytes: 4096, chunkSize: 1024), 4);
      expect(chunker.totalChunksFor(totalBytes: 4097, chunkSize: 1024), 5);
    });

    test('reads a file chunk by chunk', () async {
      const chunker = FileChunker();
      final tempDir = await Directory.systemTemp.createTemp(
        'blueshare_chunker',
      );
      final file = File('${tempDir.path}/sample.bin');
      await file.writeAsBytes(
        Uint8List.fromList(List<int>.generate(10, (index) => index)),
      );

      final chunk0 = await chunker.readChunk(
        path: file.path,
        chunkIndex: 0,
        chunkSize: 4,
      );
      final chunk1 = await chunker.readChunk(
        path: file.path,
        chunkIndex: 1,
        chunkSize: 4,
      );
      final chunk2 = await chunker.readChunk(
        path: file.path,
        chunkIndex: 2,
        chunkSize: 4,
      );

      expect(chunk0.bytes, <int>[0, 1, 2, 3]);
      expect(chunk1.bytes, <int>[4, 5, 6, 7]);
      expect(chunk2.bytes, <int>[8, 9]);

      await tempDir.delete(recursive: true);
    });
  });
}
