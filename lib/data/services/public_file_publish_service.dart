import 'package:flutter/services.dart';

class PublicFilePublishService {
  static const MethodChannel _methodChannel = MethodChannel(
    'blueshare/native_bluetooth',
  );

  Future<String?> publishReceivedFile({
    required String sourcePath,
    required String fileName,
    String? mimeType,
  }) async {
    return await _methodChannel.invokeMethod<String>('publishReceivedFile', {
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }
}
