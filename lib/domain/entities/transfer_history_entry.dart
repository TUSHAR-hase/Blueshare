import 'transfer_direction.dart';
import 'transfer_status.dart';

class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.id,
    required this.transferId,
    required this.fileName,
    required this.filePath,
    required this.remoteAddress,
    required this.direction,
    required this.totalBytes,
    required this.bytesTransferred,
    required this.status,
    required this.startedAt,
    this.remoteName,
    this.completedAt,
    this.checksum,
    this.errorMessage,
    this.sourceAddress,
    this.sourceName,
    this.originNode,
    this.hopCount = 0,
    this.forwardedToCount = 0,
    this.isRelay = false,
  });

  final String id;
  final String transferId;
  final String fileName;
  final String filePath;
  final String remoteAddress;
  final String? remoteName;
  final TransferDirection direction;
  final int totalBytes;
  final int bytesTransferred;
  final TransferStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? checksum;
  final String? errorMessage;
  final String? sourceAddress;
  final String? sourceName;
  final String? originNode;
  final int hopCount;
  final int forwardedToCount;
  final bool isRelay;

  factory TransferHistoryEntry.fromMap(Map<String, dynamic> map) {
    return TransferHistoryEntry(
      id: map['id'] as String,
      transferId: map['transferId'] as String,
      fileName: map['fileName'] as String,
      filePath: map['filePath'] as String,
      remoteAddress: map['remoteAddress'] as String,
      remoteName: map['remoteName'] as String?,
      direction: TransferDirection.values.firstWhere(
        (value) => value.name == map['direction'],
        orElse: () => TransferDirection.outgoing,
      ),
      totalBytes: map['totalBytes'] as int,
      bytesTransferred: map['bytesTransferred'] as int,
      status: TransferStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => TransferStatus.failed,
      ),
      startedAt: DateTime.parse(map['startedAt'] as String),
      completedAt:
          map['completedAt'] == null
              ? null
              : DateTime.parse(map['completedAt'] as String),
      checksum: map['checksum'] as String?,
      errorMessage: map['errorMessage'] as String?,
      sourceAddress: map['sourceAddress'] as String?,
      sourceName: map['sourceName'] as String?,
      originNode: map['originNode'] as String?,
      hopCount: map['hopCount'] as int? ?? 0,
      forwardedToCount: map['forwardedToCount'] as int? ?? 0,
      isRelay: map['isRelay'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transferId': transferId,
      'fileName': fileName,
      'filePath': filePath,
      'remoteAddress': remoteAddress,
      'remoteName': remoteName,
      'direction': direction.name,
      'totalBytes': totalBytes,
      'bytesTransferred': bytesTransferred,
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'checksum': checksum,
      'errorMessage': errorMessage,
      'sourceAddress': sourceAddress,
      'sourceName': sourceName,
      'originNode': originNode,
      'hopCount': hopCount,
      'forwardedToCount': forwardedToCount,
      'isRelay': isRelay,
    };
  }
}
