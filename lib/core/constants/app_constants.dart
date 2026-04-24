class AppConstants {
  static const appName = 'BlueShare';
  static const transferChunkSize = 4 * 1024;
  static const transferAckTimeout = Duration(seconds: 10);
  static const transferOfferTimeout = Duration(seconds: 20);
  static const transferCompleteTimeout = Duration(seconds: 20);
  static const maxChunkRetries = 3;
  static const maxControlRetries = 3;
  static const reconnectAttempts = 5;
  static const maxParallelOutgoingPerWave = 8;
  static const foregroundServiceId = 4128;
  static const protocolVersion = 1;
}
