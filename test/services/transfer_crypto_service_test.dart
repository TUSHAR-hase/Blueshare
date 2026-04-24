import 'package:blueshare/data/services/transfer_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferCryptoService', () {
    test('signs and verifies payloads with the same passkey', () async {
      final service = TransferCryptoService(sharedSecret: 'mesh-passkey-123');
      final payload = <String, dynamic>{
        'transferId': 'tx-1',
        'fileName': 'report.pdf',
        'fileSize': 4096,
        'encrypted': true,
        'hopCount': 1,
      };

      final signature = await service.signPayload(payload);

      expect(signature, isNotNull);
      expect(
        await service.verifyPayload(payload: payload, signature: signature),
        isTrue,
      );
    });

    test('rejects payloads signed with a different passkey', () async {
      final sender = TransferCryptoService(sharedSecret: 'mesh-passkey-123');
      final receiver = TransferCryptoService(sharedSecret: 'different-key');
      final payload = <String, dynamic>{
        'transferId': 'tx-2',
        'fileName': 'photo.jpg',
        'fileSize': 1024,
        'encrypted': true,
        'hopCount': 0,
      };

      final signature = await sender.signPayload(payload);

      expect(
        await receiver.verifyPayload(payload: payload, signature: signature),
        isFalse,
      );
    });

    test('updates the shared secret used for encryption and signing', () async {
      final service = TransferCryptoService();
      final payload = <String, dynamic>{
        'transferId': 'tx-3',
        'fileName': 'notes.txt',
        'fileSize': 512,
        'encrypted': true,
        'hopCount': 2,
      };

      expect(service.isEnabled, isFalse);
      expect(await service.signPayload(payload), isNull);

      service.updateSharedSecret('rotated-key');

      expect(service.isEnabled, isTrue);
      expect(await service.signPayload(payload), isNotNull);
    });
  });
}
