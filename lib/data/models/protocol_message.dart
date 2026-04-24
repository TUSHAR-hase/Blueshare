import 'dart:convert';

enum ProtocolMessageType {
  offer,
  offerAck,
  chunk,
  chunkAck,
  complete,
  completeAck,
  meshReport,
  cancel,
  error,
}

class ProtocolMessage {
  const ProtocolMessage({required this.type, required this.payload});

  final ProtocolMessageType type;
  final Map<String, dynamic> payload;

  String encode() {
    return jsonEncode({'type': type.name, 'payload': payload});
  }

  factory ProtocolMessage.decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ProtocolMessage(
      type: ProtocolMessageType.values.firstWhere(
        (value) => value.name == data['type'],
        orElse: () => ProtocolMessageType.error,
      ),
      payload: Map<String, dynamic>.from(data['payload'] as Map),
    );
  }
}
