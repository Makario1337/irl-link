import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:irllink/src/core/background/tasks_handlers/realtime_irl_task_handler.dart';

/// Keeps the app alive while the screen is locked or the app is in background,
/// so chats, TTS and sounds keep working.
///
/// Android: a foreground service (mediaPlayback) keeps the process and the
/// network running. It is shared with RealtimeIRL (location sharing).
/// iOS: a silent audio loop keeps the app from being suspended (requires the
/// "audio" background mode).
class BackgroundService extends GetxService with WidgetsBindingObserver {
  final AudioPlayer _silentPlayer = AudioPlayer();
  bool _keepAlive = false;
  bool _locationSharing = false;

  static const _keepAliveText = 'Chat and TTS keep running in background.';
  static const _locationText =
      'Your location is being shared with RealtimeIRL.';

  Future<BackgroundService> init() async {
    _initForegroundTask(locationSharing: false);
    WidgetsBinding.instance.addObserver(this);

    if (Platform.isIOS) {
      // Mix with other apps (music, streaming apps) instead of interrupting them
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await _silentPlayer.setReleaseMode(ReleaseMode.loop);
    }
    return this;
  }

  /// Called when the user is logged in and chats are running.
  Future<void> startKeepAlive() async {
    if (_keepAlive) {
      return;
    }
    _keepAlive = true;

    if (Platform.isAndroid) {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!_locationSharing) {
        await _startForegroundService();
      }
    } else if (Platform.isIOS) {
      try {
        await _silentPlayer.play(AssetSource('../lib/assets/blank.mp3'));
      } catch (e) {
        debugPrint('Failed to start background audio: $e');
      }
    }
  }

  Future<void> stopKeepAlive() async {
    if (!_keepAlive) {
      return;
    }
    _keepAlive = false;

    if (Platform.isAndroid) {
      if (!_locationSharing) {
        await FlutterForegroundTask.stopService();
      } else {
        await _updateForegroundService();
      }
    } else if (Platform.isIOS) {
      await _silentPlayer.stop();
    }
  }

  Future<ServiceRequestResult> startLocationSharing() async {
    _locationSharing = true;
    _initForegroundTask(locationSharing: true);

    // The service types can't be changed on a running service, restart it
    // with the location type (we are in foreground here, so this is allowed)
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    return _startForegroundService();
  }

  Future<void> stopLocationSharing() async {
    if (!_locationSharing) {
      return;
    }
    _locationSharing = false;
    _initForegroundTask(locationSharing: false);

    if (Platform.isAndroid && _keepAlive) {
      // Don't restart the service: this can be triggered from the
      // notification while in background, where starting a service is denied
      await _updateForegroundService();
    } else {
      await FlutterForegroundTask.stopService();
    }
  }

  void _initForegroundTask({required bool locationSharing}) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _taskOptions(locationSharing: locationSharing),
    );
  }

  ForegroundTaskOptions _taskOptions({required bool locationSharing}) {
    return ForegroundTaskOptions(
      // Only wake up the task handler when the position has to be pushed
      eventAction: locationSharing
          ? ForegroundTaskEventAction.repeat(5000)
          : ForegroundTaskEventAction.nothing(),
      allowWifiLock: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Starting a foreground service from background is denied since
    // Android 12, retry as soon as the app is visible again
    if (state == AppLifecycleState.resumed &&
        Platform.isAndroid &&
        (_keepAlive || _locationSharing)) {
      _ensureForegroundService();
    }
  }

  Future<void> _ensureForegroundService() async {
    if (!await FlutterForegroundTask.isRunningService) {
      await _startForegroundService();
    }
  }

  Future<ServiceRequestResult> _startForegroundService() async {
    final result = await _startService();
    if (result is ServiceRequestFailure) {
      debugPrint('Failed to start foreground service: ${result.error}');
    }
    return result;
  }

  Future<ServiceRequestResult> _startService() {
    return FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: [
        if (_keepAlive) ForegroundServiceTypes.mediaPlayback,
        if (_locationSharing) ForegroundServiceTypes.location,
      ],
      notificationTitle: 'IRL Link',
      notificationText: _locationSharing ? _locationText : _keepAliveText,
      notificationIcon: _notificationIcon,
      notificationButtons: _notificationButtons,
      callback: startCallback,
    );
  }

  Future<ServiceRequestResult> _updateForegroundService() {
    return FlutterForegroundTask.updateService(
      foregroundTaskOptions: _taskOptions(locationSharing: _locationSharing),
      notificationTitle: 'IRL Link',
      notificationText: _locationSharing ? _locationText : _keepAliveText,
      notificationIcon: _notificationIcon,
      notificationButtons: _notificationButtons,
    );
  }

  NotificationIcon get _notificationIcon => const NotificationIcon(
        backgroundColor: Colors.transparent,
        metaDataName: 'dev.lezd.www.irllink.service.SMALL_ICON',
      );

  List<NotificationButton> get _notificationButtons => [
        if (_locationSharing)
          const NotificationButton(id: 'rtirl_stop', text: 'Stop sharing'),
      ];

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _silentPlayer.dispose();
    super.onClose();
  }
}
