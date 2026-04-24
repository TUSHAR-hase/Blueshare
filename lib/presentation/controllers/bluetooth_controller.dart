import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/classic_transport_service.dart';
import '../../data/services/native_bluetooth_bridge.dart';
import '../../domain/entities/bluetooth_peer.dart';
import '../../domain/entities/mesh_node_role.dart';
import '../../domain/repositories/bluetooth_repository.dart';
import '../../domain/repositories/settings_repository.dart';

class BluetoothController extends ChangeNotifier {
  BluetoothController({
    required BluetoothRepository bluetoothRepository,
    required SettingsRepository settingsRepository,
  }) : _bluetoothRepository = bluetoothRepository,
       _settingsRepository = settingsRepository;

  final BluetoothRepository _bluetoothRepository;
  final SettingsRepository _settingsRepository;

  final Map<String, BluetoothPeer> _peers = <String, BluetoothPeer>{};
  final Map<String, String> _nicknames = <String, String>{};
  final Set<String> _connectedAddresses = <String>{};
  final Set<String> _pendingAutoConnects = <String>{};
  final Map<String, int> _autoConnectFailures = <String, int>{};
  final Map<String, DateTime> _nextAutoConnectAt = <String, DateTime>{};

  StreamSubscription<NativeDiscoveryEvent>? _discoverySubscription;
  StreamSubscription<TransportConnectionEvent>? _connectionSubscription;
  Timer? _meshScanTimer;
  Timer? _liveStatusTimer;

  bool _initialized = false;
  bool _disposed = false;
  bool _isScanning = false;
  bool _isBluetoothEnabled = false;
  bool _isServerRunning = false;
  bool _isConnected = false;
  String _localDeviceName = 'Unknown Device';
  MeshNodeRole _meshRole = MeshNodeRole.client;
  DateTime? _lastBluetoothCheckAt;
  DateTime? _lastPeerUpdateAt;
  DateTime? _lastScanFinishedAt;
  String? _errorMessage;

  List<BluetoothPeer> get peers {
    final entries =
        _peers.values
            .where((peer) => _isSupportedPeer(peer) && peer.isAvailableNow)
            .toList()
          ..sort((left, right) {
            if (left.isConnected != right.isConnected) {
              return left.isConnected ? -1 : 1;
            }
            if (left.isBonded != right.isBonded) {
              return left.isBonded ? -1 : 1;
            }
            return left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            );
          });
    return entries;
  }

  bool get isScanning => _isScanning;
  bool get isBluetoothEnabled => _isBluetoothEnabled;
  bool get isServerRunning => _isServerRunning;
  bool get isConnected => _isConnected;
  String get localDeviceName => _localDeviceName;
  MeshNodeRole get meshRole => _meshRole;
  List<String> get connectedAddresses =>
      _connectedAddresses.toList()..sort((a, b) => a.compareTo(b));
  int get connectedPeerCount => _connectedAddresses.length;
  String? get connectedAddress =>
      connectedAddresses.isEmpty ? null : connectedAddresses.first;
  DateTime? get lastBluetoothCheckAt => _lastBluetoothCheckAt;
  DateTime? get lastPeerUpdateAt => _lastPeerUpdateAt;
  DateTime? get lastScanFinishedAt => _lastScanFinishedAt;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _nicknames.addAll(await _settingsRepository.loadNicknames());
    _meshRole = await _settingsRepository.loadMeshRole();

    final hasPermissions = await _ensurePermissions();
    if (!hasPermissions) {
      _errorMessage =
          'Bluetooth permissions are required before BlueShare can scan or connect.';
      _notifyIfAlive();
      return;
    }

    await _bluetoothRepository.initialize();
    _localDeviceName = await _bluetoothRepository.getLocalDeviceName();
    await _refreshBluetoothStatus();
    _isServerRunning = await _bluetoothRepository.startServer();
    await _refreshBondedPeers();

    _discoverySubscription = _bluetoothRepository.watchDiscovery().listen((
      event,
    ) async {
      switch (event.type) {
        case NativeDiscoveryEventType.deviceFound:
          if (event.peer != null) {
            _lastPeerUpdateAt = DateTime.now();
            _mergePeer(event.peer!);
            unawaited(_maybeAutoConnect(event.peer!));
          }
          break;
        case NativeDiscoveryEventType.bondStateChanged:
          await _refreshBondedPeers();
          if (event.peer != null) {
            _lastPeerUpdateAt = DateTime.now();
            _mergePeer(event.peer!);
            unawaited(_maybeAutoConnect(event.peer!));
          }
          break;
        case NativeDiscoveryEventType.discoveryFinished:
          _isScanning = false;
          _lastScanFinishedAt = DateTime.now();
          await _refreshBondedPeers();
          unawaited(_connectKnownBondedPeers());
          break;
      }
      _notifyIfAlive();
    });

    _connectionSubscription = _bluetoothRepository
        .watchConnectionEvents()
        .listen((event) {
          _errorMessage =
              event.state == TransportConnectionState.error
                  ? event.errorMessage
                  : null;

          switch (event.state) {
            case TransportConnectionState.connected:
              if (event.address != null) {
                _connectedAddresses.add(event.address!);
                _clearAutoConnectBackoff(event.address!);
              }
              _isConnected = _connectedAddresses.isNotEmpty;
              _syncConnectedFlags();
              break;
            case TransportConnectionState.disconnected:
              if (event.address != null) {
                _connectedAddresses.remove(event.address!);
              } else {
                _connectedAddresses.clear();
              }
              _isConnected = _connectedAddresses.isNotEmpty;
              _syncConnectedFlags();
              break;
            case TransportConnectionState.serverStarted:
              _isServerRunning = true;
              break;
            case TransportConnectionState.serverStopped:
              _isServerRunning = false;
              break;
            case TransportConnectionState.connecting:
            case TransportConnectionState.error:
              break;
          }

          _notifyIfAlive();
        });

    _startMeshMaintenance();
    _startLiveStatusUpdates();
    unawaited(startScan());
    _notifyIfAlive();
  }

  Future<void> startScan() async {
    if (!await _ensurePermissions()) {
      _errorMessage = 'Grant Bluetooth permissions to scan nearby devices.';
      _notifyIfAlive();
      return;
    }

    await _refreshBluetoothStatus();
    if (!_isBluetoothEnabled) {
      _errorMessage = 'Turn on Bluetooth to scan nearby devices.';
      _isScanning = false;
      _notifyIfAlive();
      return;
    }

    _errorMessage = null;
    _isScanning = await _bluetoothRepository.startDiscovery();
    _notifyIfAlive();
  }

  Future<void> stopScan() async {
    await _bluetoothRepository.stopDiscovery();
    _isScanning = false;
    await _refreshBondedPeers();
    _notifyIfAlive();
  }

  Future<void> connect(String address) async {
    if (!await _ensurePermissions()) {
      _errorMessage = 'Grant Bluetooth permissions to connect to devices.';
      _notifyIfAlive();
      return;
    }

    final peer = _peers[address];
    if (peer != null && !_isSupportedPeer(peer)) {
      _errorMessage = 'BlueShare can send files only to nearby phones.';
      _notifyIfAlive();
      return;
    }
    if (peer != null && !peer.isAvailableNow && !peer.isConnected) {
      _errorMessage = 'Scan nearby devices again before connecting.';
      _notifyIfAlive();
      return;
    }

    _errorMessage = null;
    _notifyIfAlive();

    try {
      final connected = await _bluetoothRepository.connect(address);
      if (!connected) {
        _errorMessage = 'Could not connect to $address.';
      }
    } catch (error) {
      _errorMessage = 'Connection failed: $error';
    }

    _notifyIfAlive();
  }

  Future<void> disconnect([String? address]) async {
    await _bluetoothRepository.disconnect(address);
    if (address == null) {
      _connectedAddresses.clear();
    } else {
      _connectedAddresses.remove(address);
    }
    _isConnected = _connectedAddresses.isNotEmpty;
    _syncConnectedFlags();
    _notifyIfAlive();
  }

  Future<void> pairDevice(String address) async {
    if (!await _ensurePermissions()) {
      _errorMessage = 'Grant Bluetooth permissions to pair devices.';
      _notifyIfAlive();
      return;
    }

    final peer = _peers[address];
    if (peer != null && !_isSupportedPeer(peer)) {
      _errorMessage = 'BlueShare can pair for file transfer only with phones.';
      _notifyIfAlive();
      return;
    }

    final paired = await _bluetoothRepository.pairDevice(address);
    if (!paired) {
      _errorMessage = 'Pairing request was not accepted by the device.';
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    await _refreshBondedPeers();
    _notifyIfAlive();
  }

  Future<void> unpairDevice(String address) async {
    if (!await _ensurePermissions()) {
      _errorMessage = 'Grant Bluetooth permissions to unpair devices.';
      _notifyIfAlive();
      return;
    }

    final unpaired = await _bluetoothRepository.unpairDevice(address);
    if (!unpaired) {
      _errorMessage = 'Could not remove pairing from the device.';
    }
    if (_connectedAddresses.contains(address)) {
      await disconnect(address);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    await _refreshBondedPeers();
    _notifyIfAlive();
  }

  Future<void> makeDiscoverable() async {
    if (!await _ensurePermissions()) {
      _errorMessage =
          'Grant Bluetooth permissions before making this device discoverable.';
      _notifyIfAlive();
      return;
    }
    await _bluetoothRepository.makeDiscoverable();
  }

  Future<void> saveNickname(String address, String nickname) async {
    await _settingsRepository.saveNickname(address, nickname);
    if (nickname.trim().isEmpty) {
      _nicknames.remove(address);
    } else {
      _nicknames[address] = nickname.trim();
    }
    final peer = _peers[address];
    if (peer != null) {
      _peers[address] = peer.copyWith(
        nickname: nickname.trim().isEmpty ? null : nickname.trim(),
        clearNickname: nickname.trim().isEmpty,
      );
    }
    _notifyIfAlive();
  }

  Future<void> setMeshRole(MeshNodeRole role) async {
    if (_meshRole == role) {
      return;
    }
    _meshRole = role;
    await _settingsRepository.saveMeshRole(role);
    if (_meshRole == MeshNodeRole.master) {
      unawaited(_connectKnownBondedPeers());
    }
    _notifyIfAlive();
  }

  BluetoothPeer? peerByAddress(String address) {
    final peer = _peers[address];
    if (peer == null || !_isSupportedPeer(peer) || !peer.isAvailableNow) {
      return null;
    }
    return peer;
  }

  void _mergePeer(BluetoothPeer peer) {
    if (peer.address.trim().isEmpty) {
      return;
    }
    if (!_isSupportedPeer(peer)) {
      _dropUnsupportedPeer(peer.address);
      return;
    }

    final nickname = _nicknames[peer.address];
    final current = _peers[peer.address];
    final isConnected = _connectedAddresses.contains(peer.address);
    final resolvedName =
        peer.hasResolvedName
            ? peer.name
            : (current?.hasResolvedName == true ? current!.name : peer.name);
    _peers[peer.address] = (current ?? peer).copyWith(
      name: resolvedName,
      nickname: nickname,
      rssi: peer.rssi ?? current?.rssi,
      deviceClass: peer.deviceClass,
      clearDeviceClass: peer.deviceClass == null,
      majorDeviceClass: peer.majorDeviceClass,
      clearMajorDeviceClass: peer.majorDeviceClass == null,
      isBonded: peer.isBonded,
      isConnected: isConnected,
      lastSeen: peer.lastSeen ?? DateTime.now(),
    );
  }

  Future<void> _refreshBondedPeers() async {
    final bondedPeers = await _bluetoothRepository.getBondedDevices();
    final bondedAddresses = bondedPeers.map((peer) => peer.address).toSet();

    for (final entry in _peers.entries.toList()) {
      if (!_isSupportedPeer(entry.value)) {
        _dropUnsupportedPeer(entry.key);
        continue;
      }
      _peers[entry.key] = entry.value.copyWith(
        isBonded: bondedAddresses.contains(entry.key),
        isConnected: _connectedAddresses.contains(entry.key),
      );
    }

    for (final peer in bondedPeers) {
      final current = _peers[peer.address];
      if (current == null) {
        continue;
      }
      _mergePeer(
        peer.copyWith(
          name: current.name,
          nickname: current.nickname,
          rssi: current.rssi,
          isConnected: _connectedAddresses.contains(peer.address),
          lastSeen: current.lastSeen,
        ),
      );
    }

    _pruneUnavailablePeers();
  }

  void _syncConnectedFlags() {
    for (final entry in _peers.entries.toList()) {
      _peers[entry.key] = entry.value.copyWith(
        isConnected: _connectedAddresses.contains(entry.key),
      );
    }
    _pruneUnavailablePeers();
  }

  void _startMeshMaintenance() {
    _meshScanTimer?.cancel();
    _meshScanTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_performMeshMaintenance());
    });
  }

  Future<void> _performMeshMaintenance() async {
    if (!_initialized || _disposed) {
      return;
    }
    await _refreshBluetoothStatus();
    if (!_isBluetoothEnabled) {
      _isScanning = false;
      _notifyIfAlive();
      return;
    }
    if (!await _ensurePermissions()) {
      return;
    }
    if (!_isScanning) {
      _isScanning = await _bluetoothRepository.startDiscovery();
      _notifyIfAlive();
    }
    await _connectKnownBondedPeers();
  }

  Future<void> _connectKnownBondedPeers() async {
    for (final peer in peers) {
      await _maybeAutoConnect(peer);
    }
  }

  void _startLiveStatusUpdates() {
    _liveStatusTimer?.cancel();
    _liveStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshBluetoothStatus());
    });
  }

  Future<void> _refreshBluetoothStatus() async {
    try {
      final enabled = await _bluetoothRepository.isBluetoothEnabled();
      _lastBluetoothCheckAt = DateTime.now();
      if (_isBluetoothEnabled != enabled) {
        _isBluetoothEnabled = enabled;
        if (!enabled) {
          _isScanning = false;
          _connectedAddresses.clear();
          _isConnected = false;
          _syncConnectedFlags();
        }
      }
      _pruneUnavailablePeers();
      _notifyIfAlive();
    } catch (_) {
      _lastBluetoothCheckAt = DateTime.now();
      _pruneUnavailablePeers();
      _notifyIfAlive();
    }
  }

  Future<void> _maybeAutoConnect(BluetoothPeer peer) async {
    if (!_isSupportedPeer(peer) ||
        !peer.isBonded ||
        peer.isConnected ||
        _connectedAddresses.contains(peer.address) ||
        _pendingAutoConnects.contains(peer.address)) {
      return;
    }

    final nextAttemptAt = _nextAutoConnectAt[peer.address];
    if (nextAttemptAt != null && DateTime.now().isBefore(nextAttemptAt)) {
      return;
    }

    _pendingAutoConnects.add(peer.address);
    try {
      final connected = await _bluetoothRepository.connect(peer.address);
      if (connected || await _bluetoothRepository.isConnected(peer.address)) {
        _clearAutoConnectBackoff(peer.address);
      } else {
        _recordAutoConnectFailure(peer.address);
      }
    } catch (_) {
      _recordAutoConnectFailure(peer.address);
    } finally {
      _pendingAutoConnects.remove(peer.address);
    }
  }

  void _recordAutoConnectFailure(String address) {
    final failures = (_autoConnectFailures[address] ?? 0) + 1;
    _autoConnectFailures[address] = failures;
    final delaySeconds =
        failures == 1
            ? 45
            : failures == 2
            ? 90
            : failures == 3
            ? 180
            : 300;
    _nextAutoConnectAt[address] = DateTime.now().add(
      Duration(seconds: delaySeconds),
    );
  }

  void _clearAutoConnectBackoff(String address) {
    _autoConnectFailures.remove(address);
    _nextAutoConnectAt.remove(address);
  }

  Future<bool> _ensurePermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];

    if (Platform.isAndroid) {
      final sdkInt = await _bluetoothRepository.getAndroidSdkInt();
      if (sdkInt <= 30) {
        permissions.add(Permission.locationWhenInUse);
      }
      if (sdkInt >= 33) {
        permissions.add(Permission.notification);
      }
    }

    final statuses = await permissions.request();

    for (final entry in statuses.entries) {
      if (entry.key == Permission.notification) {
        continue;
      }
      if (!entry.value.isGranted && !entry.value.isLimited) {
        return false;
      }
    }
    return true;
  }

  bool _isSupportedPeer(BluetoothPeer peer) => peer.isLikelyMobileDevice;

  void _pruneUnavailablePeers() {
    for (final entry in _peers.entries.toList()) {
      final peer = entry.value;
      if (peer.isConnected || peer.isAvailableNow) {
        continue;
      }
      _peers.remove(entry.key);
    }
  }

  void _dropUnsupportedPeer(String address) {
    _peers.remove(address);
    if (_connectedAddresses.contains(address)) {
      unawaited(disconnect(address));
    }
  }

  void _notifyIfAlive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _meshScanTimer?.cancel();
    _liveStatusTimer?.cancel();
    _discoverySubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
