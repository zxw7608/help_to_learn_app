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
import '../api/api_client.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/materials',
    redirect: (context, state) async {
      final hasToken = await TokenStorage.hasToken();
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
                  return MaterialDetailPage(materialId: id);
                },
              ),
            ],
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
    ],
  );
});

// ─── Main Shell (Bottom Nav) ─────────────────────────────────────────────────

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
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = location.startsWith('/settings') ? 1 : 0;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        switch (i) {
          case 0:
            context.go('/materials');
            break;
          case 1:
            context.go('/settings');
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
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }
}
