import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedChunkPayload {
  const EncryptedChunkPayload({
    required this.bytes,
    required this.encrypted,
    this.nonce,
    this.mac,
  });

  final Uint8List bytes;
  final bool encrypted;
  final String? nonce;
  final String? mac;
}

class TransferCryptoService {
  TransferCryptoService({String? sharedSecret}) : _sharedSecret = sharedSecret;

  String? _sharedSecret;
  final _cipher = AesGcm.with256bits();
  final _mac = Hmac.sha256();

  bool get isEnabled => (_sharedSecret?.trim().isNotEmpty ?? false);

  void updateSharedSecret(String? sharedSecret) {
    final normalized = sharedSecret?.trim();
    _sharedSecret =
        normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<EncryptedChunkPayload> encrypt(Uint8List data) async {
    if (!isEnabled) {
      return EncryptedChunkPayload(bytes: data, encrypted: false);
    }

    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => Random.secure().nextInt(256)),
    );
    final secretBox = await _cipher.encrypt(
      data,
      secretKey: await _secretKey(),
      nonce: nonce,
    );

    return EncryptedChunkPayload(
      bytes: Uint8List.fromList(secretBox.cipherText),
      encrypted: true,
      nonce: base64Encode(secretBox.nonce),
      mac: base64Encode(secretBox.mac.bytes),
    );
  }

  Future<Uint8List> decrypt({
    required Uint8List data,
    required bool encrypted,
    String? nonce,
    String? mac,
  }) async {
    if (!encrypted) {
      return data;
    }

    final box = SecretBox(
      data,
      nonce: base64Decode(nonce!),
      mac: Mac(base64Decode(mac!)),
    );

    return Uint8List.fromList(
      await _cipher.decrypt(box, secretKey: await _secretKey()),
    );
  }

  Future<String?> signPayload(Map<String, dynamic> payload) async {
    if (!isEnabled) {
      return null;
    }

    final canonicalPayload = jsonEncode(_canonicalize(payload));
    final mac = await _mac.calculateMac(
      utf8.encode(canonicalPayload),
      secretKey: await _secretKey(),
    );
    return base64Encode(mac.bytes);
  }

  Future<bool> verifyPayload({
    required Map<String, dynamic> payload,
    required String? signature,
  }) async {
    final normalizedSignature = signature?.trim();
    if (!isEnabled ||
        normalizedSignature == null ||
        normalizedSignature.isEmpty) {
      return false;
    }

    final expected = await signPayload(payload);
    if (expected == null) {
      return false;
    }

    try {
      return _constantTimeEquals(
        base64Decode(expected),
        base64Decode(normalizedSignature),
      );
    } on FormatException {
      return false;
    }
  }

  Future<SecretKey> _secretKey() async {
    final seed = Uint8List.fromList(utf8.encode(_sharedSecret!));
    final digest = await Sha256().hash(seed);
    return SecretKey(digest.bytes);
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final orderedKeys =
          value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in orderedKeys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var result = 0;
    for (var index = 0; index < left.length; index++) {
      result |= left[index] ^ right[index];
    }
    return result == 0;
  }
}
