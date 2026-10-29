import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:irllink/src/core/services/background_service.dart';
import 'package:irllink/src/core/services/realtime_irl.dart';
import 'package:irllink/src/core/utils/determine_position.dart';
import 'package:irllink/src/domain/usecases/settings/get_general_settings.dart';

class RealtimeIrlViewController extends GetxController
    with WidgetsBindingObserver {
  late RealtimeIrl realtimeIrl;

  RealtimeIrlViewController({
    required this.getGeneralSettingsUseCase,
  });

  final GetGeneralSettingsUseCase getGeneralSettingsUseCase;

  @override
  void onInit() async {
    String key = '';
    final generalSettingsResult = await getGeneralSettingsUseCase();
    generalSettingsResult.fold(
      (l) {},
      (r) {
        key = r.rtIrlPushKey;
      },
    );

    realtimeIrl = RealtimeIrl(key);

    FlutterForegroundTask.addTaskDataCallback(realtimeIrl.onReceiveTaskData);
    super.onInit();
  }

  @override
  void onClose() {
    Get.find<BackgroundService>().stopLocationSharing();
    FlutterForegroundTask.removeTaskDataCallback(realtimeIrl.onReceiveTaskData);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // The app is back to the foreground
      start(); // Reconnect to RealtimeIRL service
    } else if (state == AppLifecycleState.paused) {
      // The app is sent to the background
    }
  }

  Future stop() async {
    return realtimeIrl.stopTracking();
  }

  Future start() async {
    if (Platform.isAndroid) {
      if (await Geolocator.checkPermission() == LocationPermission.denied) {
        await Get.dialog(
          barrierDismissible: false,
          AlertDialog(
            title: const Text('RealtimeIRL'),
            content: const Text(
              'This application will ask the permission to access your location to share it with RealtimeIRL service.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Get.back(result: true);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    final positionResult = await determinePosition();

    positionResult.fold(
      (l) {
        Get.snackbar(
          "Error",
          l.message,
          snackPosition: SnackPosition.BOTTOM,
          icon: const Icon(Icons.error_outline, color: Colors.red),
          borderWidth: 1,
          borderColor: Colors.red,
        );
      },
      (r) {
        Get.find<BackgroundService>().startLocationSharing();
      },
    );
  }

  Future applySettings() async {
    final generalSettingsResult = await getGeneralSettingsUseCase();
    generalSettingsResult.fold(
      (l) {},
      (r) {
        realtimeIrl.key = r.rtIrlPushKey;
      },
    );
  }
}
