import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileStorageService {
  Future<File> createIncomingTempFile({required String transferId}) async {
    final tempDirectory = await _ensureDirectory('incoming_temp');
    final tempFile = File(p.join(tempDirectory.path, '$transferId.part'));
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.create(recursive: true);
    return tempFile;
  }

  Future<void> appendBytes({
    required String filePath,
    required List<int> bytes,
  }) async {
    final file = File(filePath);
    await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  Future<String> finalizeIncomingFile({
    required String tempPath,
    required String fileName,
    required String remoteAddress,
  }) async {
    final stamp = DateTime.now();
    final dateFolder =
        '${stamp.year.toString().padLeft(4, '0')}-${stamp.month.toString().padLeft(2, '0')}-${stamp.day.toString().padLeft(2, '0')}';
    final sanitizedAddress = remoteAddress.replaceAll(':', '_');
    final targetDirectory = await _ensureDirectory(
      p.join('received', sanitizedAddress, dateFolder),
    );
    final target = File(p.join(targetDirectory.path, fileName));
    final source = File(tempPath);

    if (await target.exists()) {
      final basename = p.basenameWithoutExtension(fileName);
      final extension = p.extension(fileName);
      final alternative = File(
        p.join(
          targetDirectory.path,
          '${basename}_${stamp.millisecondsSinceEpoch}$extension',
        ),
      );
      await source.rename(alternative.path);
      return alternative.path;
    }

    await source.rename(target.path);
    return target.path;
  }

  Future<String> writeExportFile({
    required String folderName,
    required String fileName,
    required String contents,
  }) async {
    final directory = await _ensureDirectory(folderName);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  Future<Directory> _ensureDirectory(String relativePath) async {
    final root = await _rootDirectory();
    final directory = Directory(p.join(root.path, relativePath));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _rootDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final directory = Directory(p.join(external.path, 'BlueShare'));
        await directory.create(recursive: true);
        return directory;
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'BlueShare'));
    await directory.create(recursive: true);
    return directory;
  }
}
