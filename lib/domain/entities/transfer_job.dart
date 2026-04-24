import 'transfer_direction.dart';
import 'transfer_status.dart';

class TransferJob {
  const TransferJob({
    required this.id,
    required this.transferId,
    required this.fileName,
    required this.filePath,
    required this.remoteAddress,
    required this.direction,
    required this.totalBytes,
    this.remoteName,
    this.mimeType,
    this.bytesTransferred = 0,
    this.status = TransferStatus.queued,
    this.startedAt,
    this.updatedAt,
    this.completedAt,
    this.speedBytesPerSecond = 0,
    this.checksum,
    this.errorMessage,
    this.retryCount = 0,
    this.totalChunks = 0,
    this.currentChunk = 0,
    this.sourceAddress,
    this.sourceName,
    this.originNode,
    this.hopCount = 0,
    this.forwardedToCount = 0,
    this.isRelay = false,
    this.isRemoteTelemetry = false,
    this.statusDetail,
  });

  final String id;
  final String transferId;
  final String fileName;
  final String filePath;
  final String remoteAddress;
  final String? remoteName;
  final String? mimeType;
  final TransferDirection direction;
  final int totalBytes;
  final int bytesTransferred;
  final TransferStatus status;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final double speedBytesPerSecond;
  final String? checksum;
  final String? errorMessage;
  final int retryCount;
  final int totalChunks;
  final int currentChunk;
  final String? sourceAddress;
  final String? sourceName;
  final String? originNode;
  final int hopCount;
  final int forwardedToCount;
  final bool isRelay;
  final bool isRemoteTelemetry;
  final String? statusDetail;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return bytesTransferred / totalBytes;
  }

  Duration? get eta {
    if (speedBytesPerSecond <= 0 || totalBytes <= bytesTransferred) {
      return null;
    }
    final remaining = totalBytes - bytesTransferred;
    return Duration(seconds: (remaining / speedBytesPerSecond).ceil());
  }

  TransferJob copyWith({
    String? id,
    String? transferId,
    String? fileName,
    String? filePath,
    String? remoteAddress,
    String? remoteName,
    String? mimeType,
    TransferDirection? direction,
    int? totalBytes,
    int? bytesTransferred,
    TransferStatus? status,
    DateTime? startedAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    double? speedBytesPerSecond,
    String? checksum,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? retryCount,
    int? totalChunks,
    int? currentChunk,
    String? sourceAddress,
    String? sourceName,
    String? originNode,
    int? hopCount,
    int? forwardedToCount,
    bool? isRelay,
    bool? isRemoteTelemetry,
    String? statusDetail,
    bool clearStatusDetail = false,
  }) {
    return TransferJob(
      id: id ?? this.id,
      transferId: transferId ?? this.transferId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      remoteName: remoteName ?? this.remoteName,
      mimeType: mimeType ?? this.mimeType,
      direction: direction ?? this.direction,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      checksum: checksum ?? this.checksum,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      totalChunks: totalChunks ?? this.totalChunks,
      currentChunk: currentChunk ?? this.currentChunk,
      sourceAddress: sourceAddress ?? this.sourceAddress,
      sourceName: sourceName ?? this.sourceName,
      originNode: originNode ?? this.originNode,
      hopCount: hopCount ?? this.hopCount,
      forwardedToCount: forwardedToCount ?? this.forwardedToCount,
      isRelay: isRelay ?? this.isRelay,
      isRemoteTelemetry: isRemoteTelemetry ?? this.isRemoteTelemetry,
      statusDetail:
          clearStatusDetail ? null : statusDetail ?? this.statusDetail,
    );
  }
}
