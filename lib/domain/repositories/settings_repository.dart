import 'package:flutter/material.dart';

import '../entities/mesh_security_settings.dart';
import '../entities/mesh_node_role.dart';
import '../entities/mesh_transfer_tuning.dart';

abstract class SettingsRepository {
  Future<ThemeMode> loadThemeMode();
  Future<void> saveThemeMode(ThemeMode themeMode);
  Future<MeshNodeRole> loadMeshRole();
  Future<void> saveMeshRole(MeshNodeRole role);
  Future<MeshTransferTuning> loadMeshTransferTuning();
  Future<void> saveMeshTransferTuning(MeshTransferTuning tuning);
  Future<MeshSecuritySettings> loadMeshSecuritySettings();
  Future<void> saveMeshSecuritySettings(MeshSecuritySettings settings);
  Future<Map<String, String>> loadNicknames();
  Future<void> saveNickname(String address, String nickname);
}
