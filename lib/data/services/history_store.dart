import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/transfer_history_entry.dart';

class HistoryStore {
  File? _cacheFile;

  Future<List<TransferHistoryEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => TransferHistoryEntry.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList()
        .reversed
        .toList();
  }

  Future<void> save(List<TransferHistoryEntry> entries) async {
    final file = await _file();
    final encoded = jsonEncode(
      entries.reversed.map((entry) => entry.toMap()).toList(),
    );
    await file.writeAsString(encoded, flush: true);
  }

  Future<File> _file() async {
    if (_cacheFile != null) {
      return _cacheFile!;
    }

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    _cacheFile = File(p.join(directory.path, 'transfer_history.json'));
    return _cacheFile!;
  }
}
