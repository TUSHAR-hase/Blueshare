import 'package:flutter/material.dart';

import '../../domain/entities/mesh_security_settings.dart';
import '../../domain/entities/mesh_node_role.dart';
import '../../domain/entities/mesh_transfer_tuning.dart';
import '../../domain/repositories/settings_repository.dart';
import '../services/app_preferences_store.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._store);

  final AppPreferencesStore _store;

  @override
  Future<Map<String, String>> loadNicknames() => _store.loadNicknames();

  @override
  Future<ThemeMode> loadThemeMode() => _store.loadThemeMode();

  @override
  Future<MeshNodeRole> loadMeshRole() => _store.loadMeshRole();

  @override
  Future<MeshTransferTuning> loadMeshTransferTuning() =>
      _store.loadMeshTransferTuning();

  @override
  Future<MeshSecuritySettings> loadMeshSecuritySettings() =>
      _store.loadMeshSecuritySettings();

  @override
  Future<void> saveNickname(String address, String nickname) {
    return _store.saveNickname(address, nickname);
  }

  @override
  Future<void> saveMeshRole(MeshNodeRole role) {
    return _store.saveMeshRole(role);
  }

  @override
  Future<void> saveMeshTransferTuning(MeshTransferTuning tuning) {
    return _store.saveMeshTransferTuning(tuning);
  }

  @override
  Future<void> saveMeshSecuritySettings(MeshSecuritySettings settings) {
    return _store.saveMeshSecuritySettings(settings);
  }

  @override
  Future<void> saveThemeMode(ThemeMode themeMode) {
    return _store.saveThemeMode(themeMode);
  }
}
