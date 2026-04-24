import '../entities/bluetooth_peer.dart';
import '../entities/local_file_item.dart';
import '../entities/transfer_history_entry.dart';
import '../entities/transfer_job.dart';

abstract class TransferRepository {
  Stream<List<TransferJob>> watchTransfers();
  Stream<List<TransferHistoryEntry>> watchHistory();

  Future<void> initialize();
  Future<List<TransferHistoryEntry>> loadHistory();
  Future<void> queueFiles({
    required BluetoothPeer peer,
    required List<LocalFileItem> files,
  });
  Future<void> queueMeshFiles({
    required List<BluetoothPeer> peers,
    required List<LocalFileItem> files,
  });
  Future<String> exportTransferLog();
  Future<void> pause(String transferId);
  Future<void> resume(String transferId);
  Future<void> cancel(String transferId);
  Future<void> dispose();
}
