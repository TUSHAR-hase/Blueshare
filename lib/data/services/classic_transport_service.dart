import 'dart:async';

import 'package:flutter/services.dart';

enum TransportEndpoint { client, host }

enum TransportConnectionState {
  connecting,
  connected,
  disconnected,
  serverStarted,
  serverStopped,
  error,
}

class TransportMessageEvent {
  const TransportMessageEvent({
    required this.message,
    required this.endpoint,
    required this.address,
  });

  final String message;
  final TransportEndpoint endpoint;
  final String address;
}

class TransportConnectionEvent {
  const TransportConnectionEvent({
    required this.state,
    this.endpoint,
    this.address,
    this.errorMessage,
  });

  final TransportConnectionState state;
  final TransportEndpoint? endpoint;
  final String? address;
  final String? errorMessage;
}

class ClassicTransportService {
  static const MethodChannel _channel = MethodChannel('bt_classic');

  ClassicTransportService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final StreamController<TransportMessageEvent> _messageController =
      StreamController<TransportMessageEvent>.broadcast();
  final StreamController<TransportConnectionEvent> _connectionController =
      StreamController<TransportConnectionEvent>.broadcast();

  final Map<String, TransportEndpoint> _connectedPeers =
      <String, TransportEndpoint>{};
  final Map<String, Future<bool>> _pendingConnects = <String, Future<bool>>{};

  Stream<TransportMessageEvent> get messages => _messageController.stream;
  Stream<TransportConnectionEvent> get connectionEvents =>
      _connectionController.stream;
  List<String> get connectedAddresses =>
      List<String>.unmodifiable(_connectedPeers.keys);

  Future<void> initialize() async {}

  Future<bool> isBluetoothEnabled() async {
    return await _invokeBool('isBluetoothEnabled');
  }

  Future<String> getLocalDeviceName() async {
    return await _channel.invokeMethod<String>('getDeviceName') ??
        'Unknown Device';
  }

  Future<bool> startServer() async {
    return await _invokeBool('startServer');
  }

  Future<bool> stopServer() async {
    return await _invokeBool('stopServer');
  }

  Future<bool> isServerRunning() async {
    return await _invokeBool('isServerRunning');
  }

  Future<bool> makeDiscoverable() async {
    return await _invokeBool('makeDiscoverable');
  }

  Future<bool> connect(String address) async {
    if (_connectedPeers.containsKey(address)) {
      return true;
    }
    final pendingConnect = _pendingConnects[address];
    if (pendingConnect != null) {
      return pendingConnect;
    }

    _connectionController.add(
      TransportConnectionEvent(
        state: TransportConnectionState.connecting,
        endpoint: TransportEndpoint.client,
        address: address,
      ),
    );

    final connectFuture = _channel
        .invokeMethod<bool>('connectToDevice', {'address': address})
        .then((connected) => connected ?? false);
    _pendingConnects[address] = connectFuture;

    try {
      return await connectFuture;
    } finally {
      if (_pendingConnects[address] == connectFuture) {
        _pendingConnects.remove(address);
      }
    }
  }

  Future<bool> sendMessage({
    required String address,
    required String message,
  }) async {
    return await _channel.invokeMethod<bool>('sendMessage', {
          'address': address,
          'message': message,
        }) ??
        false;
  }

  Future<bool> disconnect([String? address]) async {
    return await _channel.invokeMethod<bool>('disconnect', {
          'address': address,
        }) ??
        false;
  }

  Future<bool> isConnected([String? address]) async {
    return await _channel.invokeMethod<bool>('isConnected', {
          'address': address,
        }) ??
        false;
  }

  Future<void> dispose() async {
    await _messageController.close();
    await _connectionController.close();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onConnected':
        final address = (call.arguments as Map)['address'] as String;
        _pendingConnects.remove(address);
        _connectedPeers[address] = TransportEndpoint.client;
        _connectionController.add(
          TransportConnectionEvent(
            state: TransportConnectionState.connected,
            endpoint: TransportEndpoint.client,
            address: address,
          ),
        );
        break;
      case 'onClientConnected':
        final address = (call.arguments as Map)['address'] as String;
        _pendingConnects.remove(address);
        _connectedPeers[address] = TransportEndpoint.host;
        _connectionController.add(
          TransportConnectionEvent(
            state: TransportConnectionState.connected,
            endpoint: TransportEndpoint.host,
            address: address,
          ),
        );
        break;
      case 'onDisconnected':
        final address = (call.arguments as Map?)?['address'] as String?;
        if (address != null) {
          _connectedPeers.remove(address);
        }
        _connectionController.add(
          TransportConnectionEvent(
            state: TransportConnectionState.disconnected,
            endpoint: TransportEndpoint.client,
            address: address,
          ),
        );
        break;
      case 'onClientDisconnected':
        final address = (call.arguments as Map?)?['address'] as String?;
        if (address != null) {
          _connectedPeers.remove(address);
        }
        _connectionController.add(
          TransportConnectionEvent(
            state: TransportConnectionState.disconnected,
            endpoint: TransportEndpoint.host,
            address: address,
          ),
        );
        break;
      case 'onServerStarted':
        _connectionController.add(
          const TransportConnectionEvent(
            state: TransportConnectionState.serverStarted,
          ),
        );
        break;
      case 'onServerStopped':
        _connectionController.add(
          const TransportConnectionEvent(
            state: TransportConnectionState.serverStopped,
          ),
        );
        break;
      case 'onMessageReceived':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final message = arguments['message'] as String;
        final address = arguments['address'] as String? ?? '';
        final endpointName = arguments['endpoint'] as String?;
        final endpoint =
            endpointName == TransportEndpoint.host.name
                ? TransportEndpoint.host
                : TransportEndpoint.client;
        _messageController.add(
          TransportMessageEvent(
            message: message,
            endpoint: endpoint,
            address: address,
          ),
        );
        break;
      case 'onError':
        final error =
            (call.arguments as Map?)?['error'] as String? ??
            'Unknown Bluetooth error';
        final address = (call.arguments as Map?)?['address'] as String?;
        _connectionController.add(
          TransportConnectionEvent(
            state: TransportConnectionState.error,
            endpoint: address == null ? null : _connectedPeers[address],
            address: address,
            errorMessage: error,
          ),
        );
        break;
    }
  }

  Future<bool> _invokeBool(String method) async {
    return await _channel.invokeMethod<bool>(method) ?? false;
  }
}
