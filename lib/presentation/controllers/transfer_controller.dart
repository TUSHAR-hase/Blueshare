import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/bluetooth_peer.dart';
import '../../domain/entities/local_file_item.dart';
import '../../domain/entities/transfer_history_entry.dart';
import '../../domain/entities/transfer_job.dart';
import '../../domain/repositories/transfer_repository.dart';

class TransferController extends ChangeNotifier {
  TransferController(this._transferRepository);

  final TransferRepository _transferRepository;
  StreamSubscription<List<TransferJob>>? _jobsSubscription;
  StreamSubscription<List<TransferHistoryEntry>>? _historySubscription;

  bool _initialized = false;
  List<TransferJob> _jobs = const <TransferJob>[];
  List<TransferHistoryEntry> _history = const <TransferHistoryEntry>[];

  List<TransferJob> get jobs => _jobs;
  List<TransferHistoryEntry> get history => _history;

  List<TransferJob> get activeJobs {
    return _jobs.where((job) => job.completedAt == null).toList();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    await _transferRepository.initialize();
    _history = await _transferRepository.loadHistory();
    _jobsSubscription = _transferRepository.watchTransfers().listen((jobs) {
      _jobs = jobs;
      notifyListeners();
    });
    _historySubscription = _transferRepository.watchHistory().listen((history) {
      _history = history;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> queueFiles({
    required BluetoothPeer peer,
    required List<LocalFileItem> files,
  }) {
    return _transferRepository.queueFiles(peer: peer, files: files);
  }

  Future<void> queueMeshFiles({
    required List<BluetoothPeer> peers,
    required List<LocalFileItem> files,
  }) {
    return _transferRepository.queueMeshFiles(peers: peers, files: files);
  }

  Future<String> exportTransferLog() => _transferRepository.exportTransferLog();

  Future<void> pause(String transferId) =>
      _transferRepository.pause(transferId);

  Future<void> resume(String transferId) =>
      _transferRepository.resume(transferId);

  Future<void> cancel(String transferId) =>
      _transferRepository.cancel(transferId);

  @override
  void dispose() {
    _jobsSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }
}
