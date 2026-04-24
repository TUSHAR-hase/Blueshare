import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/providers/app_providers.dart';
import '../presentation/screens/device_detail_screen.dart';
import '../presentation/screens/file_picker_screen.dart';
import '../presentation/screens/history_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/mesh_settings_screen.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/transfer_screen.dart';
import 'app_theme.dart';

class AppRoutes {
  static const splash = '/';
  static const home = '/home';
  static const device = '/device';
  static const files = '/files';
  static const transfers = '/transfers';
  static const history = '/history';
  static const meshSettings = '/mesh-settings';
}

class BlueShareApp extends ConsumerWidget {
  const BlueShareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeController = ref.watch(themeControllerProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BlueShare',
      themeMode: themeController.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppRoutes.splash:
            return MaterialPageRoute<void>(
              builder: (_) => const SplashScreen(),
            );
          case AppRoutes.home:
            return MaterialPageRoute<void>(builder: (_) => const HomeScreen());
          case AppRoutes.device:
            final address = settings.arguments! as String;
            return MaterialPageRoute<void>(
              builder: (_) => DeviceDetailScreen(peerAddress: address),
            );
          case AppRoutes.files:
            final arguments = settings.arguments;
            final filePickerArguments =
                arguments is FilePickerArguments
                    ? arguments
                    : FilePickerArguments.single(arguments! as String);
            return MaterialPageRoute<void>(
              builder: (_) => FilePickerScreen(arguments: filePickerArguments),
            );
          case AppRoutes.transfers:
            return MaterialPageRoute<void>(
              builder: (_) => const TransferScreen(),
            );
          case AppRoutes.history:
            return MaterialPageRoute<void>(
              builder: (_) => const HistoryScreen(),
            );
          case AppRoutes.meshSettings:
            return MaterialPageRoute<void>(
              builder: (_) => const MeshSettingsScreen(),
            );
          default:
            return MaterialPageRoute<void>(
              builder: (_) => const SplashScreen(),
            );
        }
      },
    );
  }
}
