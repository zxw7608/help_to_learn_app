import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'core/api/api_client.dart';
import 'core/services/audio_handler.dart';

late AudioHandler audioHandler;

class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      AppLogger.info('App detached, stopping audio service', tag: 'Main');
      unawaited((audioHandler as HelpToLearnAudioHandler).performCleanup());
    }
  }
}

Future<void> main() async {
  // Must be called before any Flutter framework usage
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logger FIRST - capture everything from startup
  await AppLogger.init();

  // Initialize API client
  await ApiClient.initialize();

  // Global Flutter error handler (UI errors)
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.fatal(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
      tag: 'FlutterError',
    );
    FlutterError.presentError(details);
  };

  // Global async error handler (modern replacement for runZonedGuarded)
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.fatal(
      'Unhandled async error',
      error: error,
      stackTrace: stack,
      tag: 'PlatformDispatcher',
    );
    return true;
  };

  // Configure audio session with speech content type to prevent ExoPlayer DSP
  // audio offload crashes on Android 14 (OnePlus/Oppo). Speech content type is
  // not offloaded, avoiding the PlatformException(2, Unexpected runtime error).
  if (!kIsWeb && Platform.isAndroid) {
    final session = await AudioSession.instance;
    if (!session.isConfigured) {
      await session.configure(const AudioSessionConfiguration.speech());
      AppLogger.info('AudioSession configured as speech', tag: 'Main');
    }
  }

  // Initialize audio background service
  audioHandler = await AudioService.init(
    builder: () => HelpToLearnAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'de.100on.study.audio',
      androidNotificationChannelName: 'Study Audio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: Color(0xFF6750A4),
    ),
  );

  WidgetsBinding.instance.addObserver(AppLifecycleObserver());
  AppLogger.info('App started successfully', tag: 'Main');
  runApp(
    ProviderScope(
      child: HelpToLearnApp(audioHandler: audioHandler),
    ),
  );
}
