import 'package:dio/dio.dart';

class VersionService {
  static const currentVersion = '0.1.0';
  static const githubRepo = 'https://github.com/zxw7608/help_to_learn_app';
  static const githubReleases =
      'https://github.com/zxw7608/help_to_learn_app/releases';
  static const _githubApi =
      'https://api.github.com/repos/zxw7608/help_to_learn_app/releases/latest';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<VersionCheckResult> checkLatestVersion() async {
    try {
      final response = await _dio.get(_githubApi);
      final tagName = response.data['tag_name'] as String?;
      if (tagName != null) {
        final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
        final hasUpdate = _compareVersions(latestVersion, currentVersion) > 0;
        return VersionCheckResult(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          hasUpdate: hasUpdate,
          releaseUrl:
              response.data['html_url'] as String? ?? githubReleases,
        );
      }
    } catch (_) {
      // Offline or rate-limited — return gracefully
    }
    return VersionCheckResult(
      currentVersion: currentVersion,
      latestVersion: null,
      hasUpdate: false,
      releaseUrl: githubReleases,
    );
  }

  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal > bVal) return 1;
      if (aVal < bVal) return -1;
    }
    return 0;
  }
}

class VersionCheckResult {
  final String currentVersion;
  final String? latestVersion;
  final bool hasUpdate;
  final String releaseUrl;

  const VersionCheckResult({
    required this.currentVersion,
    this.latestVersion,
    required this.hasUpdate,
    required this.releaseUrl,
  });
}
