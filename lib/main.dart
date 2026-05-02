import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'core/api/api_client.dart';
import 'core/services/custom_audio_service.dart';
import 'core/services/playlist_manager.dart';

late CustomAudioService audioService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.init();
  await ApiClient.initialize();
  await TokenStorage.initSync();

  // Global Flutter error handler
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.fatal(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
      tag: 'FlutterError',
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.fatal(
      'Unhandled async error',
      error: error,
      stackTrace: stack,
      tag: 'PlatformDispatcher',
    );
    return true;
  };

  // Request notification permission on Android 13+
  if (!kIsWeb && Platform.isAndroid) {
    final status = await Permission.notification.status;
    AppLogger.info('Notification permission status: $status', tag: 'Main');
    if (status.isDenied) {
      final result = await Permission.notification.request();
      AppLogger.info('Notification permission result: $result', tag: 'Main');
    }
  }

  // Initialize custom audio service
  audioService = CustomAudioService();
  PlaylistManager.setAudioService(audioService);

  // Listen for native Android lifecycle signals
  const lifecycleChannel = MethodChannel('app_lifecycle');
  lifecycleChannel.setMethodCallHandler((call) async {
    if (call.method == 'onDestroy') {
      AppLogger.info('Received onDestroy from native, cleaning up audio', tag: 'Main');
      await audioService.performCleanup();
    }
  });

  AppLogger.info('App started successfully', tag: 'Main');
  runApp(
    ProviderScope(
      child: HelpToLearnApp(audioService: audioService),
    ),
  );
}
