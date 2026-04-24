import '../../domain/entities/bluetooth_peer.dart';
import '../../domain/repositories/bluetooth_repository.dart';
import '../services/classic_transport_service.dart';
import '../services/native_bluetooth_bridge.dart';

class BluetoothRepositoryImpl implements BluetoothRepository {
  BluetoothRepositoryImpl(this._transportService, this._nativeBridge);

  final ClassicTransportService _transportService;
  final NativeBluetoothBridge _nativeBridge;

  @override
  Future<bool> connect(String address) => _transportService.connect(address);

  @override
  Future<bool> disconnect([String? address]) =>
      _transportService.disconnect(address);

  @override
  Future<void> dispose() async {
    await _transportService.dispose();
  }

  @override
  Future<List<BluetoothPeer>> getBondedDevices() =>
      _nativeBridge.getBondedDevices();

  @override
  Future<int> getAndroidSdkInt() => _nativeBridge.getAndroidSdkInt();

  @override
  Future<String> getLocalDeviceName() => _transportService.getLocalDeviceName();

  @override
  Future<void> initialize() => _transportService.initialize();

  @override
  Future<bool> isBluetoothEnabled() => _nativeBridge.isBluetoothEnabled();

  @override
  Future<bool> isConnected([String? address]) =>
      _transportService.isConnected(address);

  @override
  Future<bool> isServerRunning() => _transportService.isServerRunning();

  @override
  Future<bool> makeDiscoverable() => _transportService.makeDiscoverable();

  @override
  Future<bool> pairDevice(String address) => _nativeBridge.pairDevice(address);

  @override
  Future<bool> sendMessage({
    required String address,
    required String message,
  }) => _transportService.sendMessage(address: address, message: message);

  @override
  Future<bool> startDiscovery() => _nativeBridge.startDiscovery();

  @override
  Future<bool> startServer() => _transportService.startServer();

  @override
  Future<bool> stopDiscovery() => _nativeBridge.stopDiscovery();

  @override
  Future<bool> stopServer() => _transportService.stopServer();

  @override
  Future<bool> unpairDevice(String address) =>
      _nativeBridge.unpairDevice(address);

  @override
  Stream<TransportConnectionEvent> watchConnectionEvents() =>
      _transportService.connectionEvents;

  @override
  Stream<NativeDiscoveryEvent> watchDiscovery() => _nativeBridge.watchEvents();
}
