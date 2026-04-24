class MeshTransferTuning {
  const MeshTransferTuning({
    this.chunkRetries = 3,
    this.controlRetries = 3,
    this.reconnectAttempts = 5,
    this.parallelOutgoingPerWave = 8,
    this.retryBackoffSeconds = 2,
  });

  final int chunkRetries;
  final int controlRetries;
  final int reconnectAttempts;
  final int parallelOutgoingPerWave;
  final int retryBackoffSeconds;

  MeshTransferTuning copyWith({
    int? chunkRetries,
    int? controlRetries,
    int? reconnectAttempts,
    int? parallelOutgoingPerWave,
    int? retryBackoffSeconds,
  }) {
    return MeshTransferTuning(
      chunkRetries: chunkRetries ?? this.chunkRetries,
      controlRetries: controlRetries ?? this.controlRetries,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      parallelOutgoingPerWave:
          parallelOutgoingPerWave ?? this.parallelOutgoingPerWave,
      retryBackoffSeconds: retryBackoffSeconds ?? this.retryBackoffSeconds,
    );
  }
}
