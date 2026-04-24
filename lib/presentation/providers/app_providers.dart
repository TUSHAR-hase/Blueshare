import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/bluetooth_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/transfer_repository_impl.dart';
import '../../data/services/app_preferences_store.dart';
import '../../data/services/background_transfer_service.dart';
import '../../data/services/checksum_service.dart';
import '../../data/services/classic_transport_service.dart';
import '../../data/services/file_chunker.dart';
import '../../data/services/file_storage_service.dart';
import '../../data/services/history_store.dart';
import '../../data/services/native_bluetooth_bridge.dart';
import '../../data/services/public_file_publish_service.dart';
import '../../data/services/transfer_crypto_service.dart';
import '../../domain/repositories/bluetooth_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../controllers/bluetooth_controller.dart';
import '../controllers/bootstrap_controller.dart';
import '../controllers/theme_controller.dart';
import '../controllers/transfer_controller.dart';

final appPreferencesStoreProvider = Provider<AppPreferencesStore>(
  (ref) => AppPreferencesStore(),
);

final historyStoreProvider = Provider<HistoryStore>((ref) => HistoryStore());

final checksumServiceProvider = Provider<ChecksumService>(
  (ref) => ChecksumService(),
);

final fileChunkerProvider = Provider<FileChunker>((ref) => const FileChunker());

final fileStorageServiceProvider = Provider<FileStorageService>(
  (ref) => FileStorageService(),
);

final backgroundTransferServiceProvider = Provider<BackgroundTransferService>(
  (ref) => BackgroundTransferService(),
);

final nativeBluetoothBridgeProvider = Provider<NativeBluetoothBridge>(
  (ref) => NativeBluetoothBridge(),
);

final publicFilePublishServiceProvider = Provider<PublicFilePublishService>(
  (ref) => PublicFilePublishService(),
);

final classicTransportServiceProvider = Provider<ClassicTransportService>(
  (ref) => ClassicTransportService(),
);

final transferCryptoServiceProvider = Provider<TransferCryptoService>(
  (ref) => TransferCryptoService(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(appPreferencesStoreProvider)),
);

final bluetoothRepositoryProvider = Provider<BluetoothRepository>(
  (ref) => BluetoothRepositoryImpl(
    ref.watch(classicTransportServiceProvider),
    ref.watch(nativeBluetoothBridgeProvider),
  ),
);

final transferRepositoryProvider = Provider<TransferRepository>(
  (ref) => TransferRepositoryImpl(
    transportService: ref.watch(classicTransportServiceProvider),
    checksumService: ref.watch(checksumServiceProvider),
    fileChunker: ref.watch(fileChunkerProvider),
    fileStorageService: ref.watch(fileStorageServiceProvider),
    historyStore: ref.watch(historyStoreProvider),
    backgroundTransferService: ref.watch(backgroundTransferServiceProvider),
    publicFilePublishService: ref.watch(publicFilePublishServiceProvider),
    transferCryptoService: ref.watch(transferCryptoServiceProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final themeControllerProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => ThemeController(ref.watch(settingsRepositoryProvider)),
);

final bluetoothControllerProvider = ChangeNotifierProvider<BluetoothController>(
  (ref) => BluetoothController(
    bluetoothRepository: ref.watch(bluetoothRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final transferControllerProvider = ChangeNotifierProvider<TransferController>(
  (ref) => TransferController(ref.watch(transferRepositoryProvider)),
);

final bootstrapControllerProvider = ChangeNotifierProvider<BootstrapController>(
  (ref) => BootstrapController(
    themeController: ref.watch(themeControllerProvider),
    bluetoothController: ref.watch(bluetoothControllerProvider),
    transferController: ref.watch(transferControllerProvider),
  ),
);
