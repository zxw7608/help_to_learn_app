import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' as app_main;
import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/materials/materials_list_page.dart';
import '../../features/materials/material_detail_page.dart';
import '../../features/materials/add_material_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/log_viewer_page.dart';
import '../../features/settings/analysis_records_page.dart';
import '../../features/player/player_page.dart';
import '../../features/playlist/playlist_page.dart';
import '../api/api_client.dart';
import '../services/custom_audio_service.dart';
import '../services/playlist_manager.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/materials',
    redirect: (context, state) {
      final hasToken = TokenStorage.hasTokenSync;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      if (!hasToken && !isAuthRoute) return '/auth/login';
      if (hasToken && isAuthRoute) return '/materials';
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/auth/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/auth/register',
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),

      // Main shell with bottom navigation — StatefulShellRoute preserves
      // sub-route state (e.g. /materials/:id) when top-level routes like
      // /player are pushed/popped on the root navigator.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/materials',
                name: 'materials',
                builder: (context, state) => const MaterialsListPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'material-detail',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      final autoPlay =
                          state.uri.queryParameters['autoPlay'] == 'true';
                      return MaterialDetailPage(
                          materialId: id, autoPlay: autoPlay);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playlist',
                name: 'playlist',
                builder: (context, state) => const PlaylistPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'logs',
                    name: 'log-viewer',
                    builder: (context, state) => const LogViewerPage(),
                  ),
                  GoRoute(
                    path: 'analysis-records',
                    name: 'analysis-records',
                    builder: (context, state) =>
                        const AnalysisRecordsPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Full-screen routes
      GoRoute(
        path: '/add-material',
        name: 'add-material',
        builder: (context, state) {
          final initialUrl = state.uri.queryParameters['url'];
          return AddMaterialPage(initialUrl: initialUrl);
        },
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        builder: (context, state) => const PlayerPage(),
      ),
      GoRoute(
        path: '/material/:id',
        name: 'material-standalone',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return MaterialDetailPage(materialId: id);
        },
      ),
    ],
  );
});

// ─── Main Shell (Bottom Nav) ─────────────────────────────────────────────────

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _GlobalMiniPlayerBar(),
          _BottomNav(navigationShell: navigationShell),
        ],
      ),
    );
  }
}

// ─── Global Mini Player Bar ─────────────────────────────────────────────────

class _GlobalMiniPlayerBar extends ConsumerWidget {
  const _GlobalMiniPlayerBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistManagerProvider);
    final notifier = ref.read(playlistManagerProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    if (!playlist.hasCurrent) return const SizedBox.shrink();

    return ValueListenableBuilder<PlaybackInfo>(
      valueListenable: app_main.audioService.playbackInfo,
      builder: (ctx, info, _) {
        final isPlaying = info.playing;
        final current = playlist.current;
        if (current == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            if (GoRouterState.of(context).uri.toString() != '/player') {
              context.push('/player');
            }
          },
          child: Container(
            height: 56,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      app_main.audioService.pause();
                    } else if (!info.hasSource) {
                      notifier.playFromCurrent();
                    } else {
                      app_main.audioService.play();
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPlaying ? '正在播放' : '已暂停',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPlaying ? cs.primary : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => notifier.cycleMode(),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          info.playModeLabel,
                          style: const TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Bottom Nav ──────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _BottomNav({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: navigationShell.currentIndex,
      onTap: (i) {
        navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        );
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.library_books_outlined),
          activeIcon: Icon(Icons.library_books),
          label: '素材库',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.queue_music_outlined),
          activeIcon: Icon(Icons.queue_music),
          label: '播放列表',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }
}
