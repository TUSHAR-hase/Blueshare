import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/constants/app_constants.dart';

@pragma('vm:entry-point')
void blueShareForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(BlueShareTaskHandler());
}

class BlueShareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class BackgroundTransferService {
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'blueshare_transfers',
        channelName: 'BlueShare Transfers',
        channelDescription:
            'Keeps Bluetooth transfers alive while BlueShare runs in the background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (Platform.isAndroid) {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }

    _initialized = true;
  }

  Future<void> showTransferNotification({
    required String title,
    required String text,
  }) async {
    await initialize();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }

      await FlutterForegroundTask.startService(
        serviceId: AppConstants.foregroundServiceId,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        callback: blueShareForegroundCallback,
      );
    } catch (_) {
      // Transfer should continue even if the OS rejects foreground notification startup.
    }
  }

  Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
