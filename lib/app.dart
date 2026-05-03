import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/custom_audio_service.dart';

class HelpToLearnApp extends ConsumerStatefulWidget {
  final CustomAudioService audioService;
  const HelpToLearnApp({super.key, required this.audioService});

  @override
  ConsumerState<HelpToLearnApp> createState() => _HelpToLearnAppState();
}

class _HelpToLearnAppState extends ConsumerState<HelpToLearnApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.info('didChangeAppLifecycleState ${state.name}', tag: 'App');
    if (state == AppLifecycleState.detached) {
      AppLogger.info('App lifecycle detached, performing audio cleanup', tag: 'App');
      widget.audioService.performCleanup();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Help To Learn',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
