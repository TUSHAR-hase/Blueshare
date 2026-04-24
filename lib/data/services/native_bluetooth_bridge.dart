import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/bluetooth_peer.dart';

enum NativeDiscoveryEventType {
  deviceFound,
  discoveryFinished,
  bondStateChanged,
}

class NativeDiscoveryEvent {
  const NativeDiscoveryEvent({required this.type, this.peer});

  final NativeDiscoveryEventType type;
  final BluetoothPeer? peer;
}

class NativeBluetoothBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'blueshare/native_bluetooth',
  );
  static const EventChannel _eventChannel = EventChannel(
    'blueshare/native_bluetooth/events',
  );

  Stream<NativeDiscoveryEvent>? _events;

  Stream<NativeDiscoveryEvent> watchEvents() {
    _events ??=
        _eventChannel.receiveBroadcastStream().map((dynamic event) {
          final map = Map<String, dynamic>.from(event as Map);
          final eventName = map['event'] as String? ?? 'device';

          if (eventName == 'finished') {
            return const NativeDiscoveryEvent(
              type: NativeDiscoveryEventType.discoveryFinished,
            );
          }

          final peer = BluetoothPeer(
            address: map['address'] as String? ?? '',
            name: map['name'] as String? ?? '',
            rssi: map['rssi'] as int?,
            deviceClass: map['deviceClass'] as int?,
            majorDeviceClass: map['majorDeviceClass'] as int?,
            isBonded: map['bonded'] as bool? ?? false,
            lastSeen: DateTime.now(),
          );

          return NativeDiscoveryEvent(
            type:
                eventName == 'bond_state'
                    ? NativeDiscoveryEventType.bondStateChanged
                    : NativeDiscoveryEventType.deviceFound,
            peer: peer,
          );
        }).asBroadcastStream();

    return _events!;
  }

  Future<List<BluetoothPeer>> getBondedDevices() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>(
      'getBondedDevices',
    );
    if (result == null) {
      return const [];
    }

    return result
        .map(
          (item) => BluetoothPeer(
            address: (item as Map)['address'] as String,
            name: item['name'] as String? ?? '',
            deviceClass: item['deviceClass'] as int?,
            majorDeviceClass: item['majorDeviceClass'] as int?,
            isBonded: true,
          ),
        )
        .toList();
  }

  Future<bool> startDiscovery() async {
    return await _methodChannel.invokeMethod<bool>('startDiscovery') ?? false;
  }

  Future<bool> stopDiscovery() async {
    return await _methodChannel.invokeMethod<bool>('stopDiscovery') ?? false;
  }

  Future<bool> pairDevice(String address) async {
    return await _methodChannel.invokeMethod<bool>('pairDevice', {
          'address': address,
        }) ??
        false;
  }

  Future<bool> unpairDevice(String address) async {
    return await _methodChannel.invokeMethod<bool>('unpairDevice', {
          'address': address,
        }) ??
        false;
  }

  Future<bool> isBluetoothEnabled() async {
    return await _methodChannel.invokeMethod<bool>('isBluetoothEnabled') ??
        false;
  }

  Future<int> getAndroidSdkInt() async {
    return await _methodChannel.invokeMethod<int>('getAndroidSdkInt') ?? 0;
  }
}
