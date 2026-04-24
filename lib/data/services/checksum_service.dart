import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ChecksumService {
  Future<String> sha256File(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  String sha256Bytes(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  String sha256Text(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
