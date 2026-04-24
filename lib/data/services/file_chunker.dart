import 'dart:io';
import 'dart:typed_data';

class FileChunk {
  const FileChunk({
    required this.index,
    required this.offset,
    required this.bytes,
  });

  final int index;
  final int offset;
  final Uint8List bytes;
}

class FileChunker {
  const FileChunker();

  int totalChunksFor({required int totalBytes, required int chunkSize}) {
    if (totalBytes <= 0) {
      return 0;
    }
    return ((totalBytes - 1) ~/ chunkSize) + 1;
  }

  Future<FileChunk> readChunk({
    required String path,
    required int chunkIndex,
    required int chunkSize,
  }) async {
    final file = File(path);
    final raf = await file.open();
    try {
      final offset = chunkIndex * chunkSize;
      await raf.setPosition(offset);
      final bytes = await raf.read(chunkSize);
      return FileChunk(
        index: chunkIndex,
        offset: offset,
        bytes: Uint8List.fromList(bytes),
      );
    } finally {
      await raf.close();
    }
  }
}
