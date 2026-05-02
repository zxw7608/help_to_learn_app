import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/materials/materials_list_page.dart';
import '../../features/materials/material_detail_page.dart';
import '../../features/materials/add_material_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/log_viewer_page.dart';
import '../../features/player/player_page.dart';
import '../../features/playlist/playlist_page.dart';
import '../api/api_client.dart';

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

      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
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
                  final autoPlay = state.uri.queryParameters['autoPlay'] == 'true';
                  return MaterialDetailPage(materialId: id, autoPlay: autoPlay);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/playlist',
            name: 'playlist',
            builder: (context, state) => const PlaylistPage(),
          ),
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

String _lastMaterialsPath = '/materials';
String _lastPlaylistPath = '/playlist';
String _lastSettingsPath = '/settings';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    // Track last path for each tab
    if (location.startsWith('/playlist')) {
      _lastPlaylistPath = location;
    } else if (location.startsWith('/settings')) {
      _lastSettingsPath = location;
    } else {
      _lastMaterialsPath = location;
    }

    int currentIndex;
    if (location.startsWith('/playlist')) {
      currentIndex = 1;
    } else if (location.startsWith('/settings')) {
      currentIndex = 2;
    } else {
      currentIndex = 0;
    }

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        switch (i) {
          case 0:
            if (location.startsWith('/materials')) {
              context.go('/materials');
            } else {
              context.go(_lastMaterialsPath);
            }
            break;
          case 1:
            if (location.startsWith('/playlist')) {
              context.go('/playlist');
            } else {
              context.go(_lastPlaylistPath);
            }
            break;
          case 2:
            if (location.startsWith('/settings')) {
              context.go('/settings');
            } else {
              context.go(_lastSettingsPath);
            }
            break;
        }
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
