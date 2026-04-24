import 'package:flutter/foundation.dart';

import 'bluetooth_controller.dart';
import 'theme_controller.dart';
import 'transfer_controller.dart';

class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required ThemeController themeController,
    required BluetoothController bluetoothController,
    required TransferController transferController,
  }) : _themeController = themeController,
       _bluetoothController = bluetoothController,
       _transferController = transferController;

  final ThemeController _themeController;
  final BluetoothController _bluetoothController;
  final TransferController _transferController;

  bool _loading = false;
  bool _ready = false;
  bool _disposed = false;
  String? _errorMessage;

  bool get loading => _loading;
  bool get ready => _ready;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_loading || _ready) {
      return;
    }

    _loading = true;
    _errorMessage = null;
    _notifyIfAlive();

    try {
      await _themeController.initialize();
      await _bluetoothController.initialize();
      await _transferController.initialize();
      _ready = true;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loading = false;
      _notifyIfAlive();
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
    super.dispose();
  }
}
