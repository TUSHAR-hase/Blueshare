import '../entities/bluetooth_peer.dart';
import '../../data/services/classic_transport_service.dart';
import '../../data/services/native_bluetooth_bridge.dart';

abstract class BluetoothRepository {
  Stream<NativeDiscoveryEvent> watchDiscovery();
  Stream<TransportConnectionEvent> watchConnectionEvents();

  Future<void> initialize();
  Future<bool> isBluetoothEnabled();
  Future<int> getAndroidSdkInt();
  Future<String> getLocalDeviceName();
  Future<bool> startServer();
  Future<bool> stopServer();
  Future<bool> makeDiscoverable();
  Future<bool> startDiscovery();
  Future<bool> stopDiscovery();
  Future<List<BluetoothPeer>> getBondedDevices();
  Future<bool> connect(String address);
  Future<bool> disconnect([String? address]);
  Future<bool> pairDevice(String address);
  Future<bool> unpairDevice(String address);
  Future<bool> sendMessage({required String address, required String message});
  Future<bool> isConnected([String? address]);
  Future<bool> isServerRunning();
  Future<void> dispose();
}
