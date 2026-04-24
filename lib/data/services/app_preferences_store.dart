import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/mesh_security_settings.dart';
import '../../domain/entities/mesh_node_role.dart';
import '../../domain/entities/mesh_transfer_tuning.dart';

class AppPreferencesStore {
  static const _themeKey = 'theme_mode';
  static const _nicknamePrefix = 'nickname_';
  static const _meshRoleKey = 'mesh_role';
  static const _chunkRetriesKey = 'mesh_chunk_retries';
  static const _controlRetriesKey = 'mesh_control_retries';
  static const _reconnectAttemptsKey = 'mesh_reconnect_attempts';
  static const _parallelOutgoingKey = 'mesh_parallel_outgoing';
  static const _retryBackoffKey = 'mesh_retry_backoff_seconds';
  static const _meshPasskeyKey = 'mesh_passkey';

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeMode.name);
  }

  Future<MeshNodeRole> loadMeshRole() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_meshRoleKey);
    return MeshNodeRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => MeshNodeRole.client,
    );
  }

  Future<void> saveMeshRole(MeshNodeRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_meshRoleKey, role.name);
  }

  Future<MeshTransferTuning> loadMeshTransferTuning() async {
    final prefs = await SharedPreferences.getInstance();
    return MeshTransferTuning(
      chunkRetries: prefs.getInt(_chunkRetriesKey) ?? 3,
      controlRetries: prefs.getInt(_controlRetriesKey) ?? 3,
      reconnectAttempts: prefs.getInt(_reconnectAttemptsKey) ?? 5,
      parallelOutgoingPerWave: prefs.getInt(_parallelOutgoingKey) ?? 8,
      retryBackoffSeconds: prefs.getInt(_retryBackoffKey) ?? 2,
    );
  }

  Future<void> saveMeshTransferTuning(MeshTransferTuning tuning) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chunkRetriesKey, tuning.chunkRetries);
    await prefs.setInt(_controlRetriesKey, tuning.controlRetries);
    await prefs.setInt(_reconnectAttemptsKey, tuning.reconnectAttempts);
    await prefs.setInt(_parallelOutgoingKey, tuning.parallelOutgoingPerWave);
    await prefs.setInt(_retryBackoffKey, tuning.retryBackoffSeconds);
  }

  Future<MeshSecuritySettings> loadMeshSecuritySettings() async {
    final prefs = await SharedPreferences.getInstance();
    return MeshSecuritySettings(
      passkey: prefs.getString(_meshPasskeyKey) ?? '',
    );
  }

  Future<void> saveMeshSecuritySettings(MeshSecuritySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final value = settings.normalizedPasskey;
    if (value.isEmpty) {
      await prefs.remove(_meshPasskeyKey);
      return;
    }
    await prefs.setString(_meshPasskeyKey, value);
  }

  Future<Map<String, String>> loadNicknames() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_nicknamePrefix)) {
        continue;
      }
      final value = prefs.getString(key);
      if (value != null && value.trim().isNotEmpty) {
        values[key.replaceFirst(_nicknamePrefix, '')] = value;
      }
    }
    return values;
  }

  Future<void> saveNickname(String address, String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_nicknamePrefix$address';
    if (nickname.trim().isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, nickname.trim());
  }
}
