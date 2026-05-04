import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/app_logger.dart';
import '../../core/api/api_client.dart';
import '../../core/api/users_api.dart';
import '../../core/services/anki_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/playlist_manager.dart';
import '../../core/services/version_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _serverUrlCtrl = TextEditingController();
  final _ankiDeckCtrl = TextEditingController();
  final _ankiModelCtrl = TextEditingController();
  final _aiBaseUrlCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController();
  final _aiApiKeyCtrl = TextEditingController();
  final _aiPromptCtrl = TextEditingController();
  bool _loadingUser = true;
  bool _saving = false;
  int _cacheBytes = 0;
  List<Map<String, dynamic>> _ankiDecks = [];
  List<Map<String, dynamic>> _ankiModels = [];
  bool _ankiAvailable = false;
  bool _detectingAnki = false;
  bool _checkingUpdate = false;
  VersionCheckResult? _versionResult;

  final _versionService = VersionService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkAnki();
    _loadCacheSize();
    AppLogger.info('SettingsPage opened', tag: 'Settings');
  }

  @override
  void dispose() {
    _serverUrlCtrl.dispose();
    _ankiDeckCtrl.dispose();
    _ankiModelCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _aiModelCtrl.dispose();
    _aiApiKeyCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _serverUrlCtrl.text = ApiClient.baseUrl;
    try {
      final user = await usersApi.getMe();
      setState(() {
        _ankiDeckCtrl.text = user.ankiDeckName;
        _ankiModelCtrl.text = user.ankiModelName;
        _aiBaseUrlCtrl.text = user.aiBaseUrl ?? '';
        _aiModelCtrl.text = user.aiModel ?? '';
        _aiApiKeyCtrl.text = ''; // Sensitive, not returned by API
        _aiPromptCtrl.text = user.aiPrompt ?? '';
        _loadingUser = false;
      });
    } catch (e) {
      setState(() => _loadingUser = false);
    }
  }

  Future<void> _checkAnki() async {
    setState(() => _detectingAnki = true);
    final available = await AnkiService.instance.isAvailable();
    if (!available) {
      setState(() {
        _ankiAvailable = false;
        _ankiDecks = [];
        _ankiModels = [];
        _detectingAnki = false;
      });
      return;
    }
    final hasPermission = await AnkiService.instance.requestPermission();
    if (!hasPermission) {
      setState(() {
        _ankiAvailable = false;
        _ankiDecks = [];
        _ankiModels = [];
        _detectingAnki = false;
      });
      return;
    }
    final decks = await AnkiService.instance.getDeckList();
    final models = await AnkiService.instance.getModelList();
    setState(() {
      _ankiAvailable = true;
      _ankiDecks = decks;
      _ankiModels = models;
      _detectingAnki = false;
    });
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheService.instance.getCacheSize();
    setState(() => _cacheBytes = size);
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      // Update server URL
      final newUrl = _serverUrlCtrl.text.trim();
      if (newUrl.isNotEmpty) {
        await ApiClient.setBaseUrl(newUrl);
      }
      // Update user Anki settings via backend
      await usersApi.updateMe(
        ankiDeckName: _ankiDeckCtrl.text.trim(),
        ankiModelName: _ankiModelCtrl.text.trim(),
        aiBaseUrl: _aiBaseUrlCtrl.text.trim().isEmpty
            ? null
            : _aiBaseUrlCtrl.text.trim(),
        aiModel: _aiModelCtrl.text.trim().isEmpty
            ? null
            : _aiModelCtrl.text.trim(),
        aiApiKey: _aiApiKeyCtrl.text.trim().isEmpty
            ? null
            : _aiApiKeyCtrl.text.trim(),
        aiPrompt: _aiPromptCtrl.text.trim().isEmpty
            ? null
            : _aiPromptCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 设置已保存')),
        );
      }
      AppLogger.info('Settings saved', tag: 'Settings');
    } catch (e, st) {
      AppLogger.error('Failed to save settings',
          tag: 'Settings', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ 保存失败: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账户？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await TokenStorage.clear();
      ref.read(playlistManagerProvider.notifier).clear();
      if (mounted) context.go('/auth/login');
    }
  }

  Future<void> _clearCache() async {
    await CacheService.instance.clearAll();
    await _loadCacheSize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 缓存已清除')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _checkVersion() async {
    setState(() => _checkingUpdate = true);
    try {
      final result = await _versionService.checkLatestVersion();
      if (mounted) {
        setState(() {
          _versionResult = result;
          _checkingUpdate = false;
        });
        final msg = result.hasUpdate
            ? '发现新版本: ${result.latestVersion}'
            : result.latestVersion != null
                ? '已是最新版本'
                : '无法获取更新信息，请检查网络';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查更新失败，请检查网络连接')),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Fallback: try platform default
      try {
        await launchUrl(Uri.parse(url));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法打开链接: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveSettings,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _loadingUser
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Server Settings ──────────────────────────────────────────
                _SectionHeader(title: '服务器', icon: Icons.cloud_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _serverUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        helperText: '默认: https://study.100on.de',
                        prefixIcon: Icon(Icons.language),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Anki Settings ────────────────────────────────────────────
                _SectionHeader(title: 'AnkiDroid', icon: Icons.style_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (!_ankiAvailable)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    color: Colors.orange, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'AnkiDroid 未检测到或无权限。请先安装并授权 AnkiDroid。',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Deck selection
                        if (_ankiDecks.isNotEmpty)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _ankiDeckCtrl.text.isEmpty
                                ? null
                                : _ankiDeckCtrl.text,
                            decoration: const InputDecoration(
                                labelText: '目标牌组', prefixIcon: Icon(Icons.folder_open)),
                            items: _ankiDecks
                                .map((d) => DropdownMenuItem<String>(
                                      value: d['name'] as String,
                                      child: Text(
                                        d['name'] as String,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _ankiDeckCtrl.text = v ?? ''),
                          )
                        else
                          TextFormField(
                            controller: _ankiDeckCtrl,
                            decoration: const InputDecoration(
                              labelText: '目标牌组名称',
                              prefixIcon: Icon(Icons.folder_open),
                              helperText: '在 AnkiDroid 中已存在的牌组名',
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Model selection
                        if (_ankiModels.isNotEmpty)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _ankiModelCtrl.text.isEmpty
                                ? null
                                : _ankiModelCtrl.text,
                            decoration: const InputDecoration(
                                labelText: '笔记类型', prefixIcon: Icon(Icons.view_agenda)),
                            items: _ankiModels
                                .map((m) => DropdownMenuItem<String>(
                                      value: m['name'] as String,
                                      child: Text(
                                        m['name'] as String,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _ankiModelCtrl.text = v ?? ''),
                          )
                        else
                          TextFormField(
                            controller: _ankiModelCtrl,
                            decoration: const InputDecoration(
                              labelText: '笔记类型 (Note Type)',
                              prefixIcon: Icon(Icons.view_agenda),
                              helperText: '例如: Basic, HelpToLearn',
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Re-detect button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _detectingAnki ? null : _checkAnki,
                            icon: _detectingAnki
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(_detectingAnki ? '检测中...' : '重新检测 AnkiDroid'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── AI Config ────────────────────────────────────────────────
                _SectionHeader(
                    title: 'AI 解析', icon: Icons.psychology_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _aiBaseUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'API Base URL',
                            helperText:
                                'OpenAI兼容API地址 (留空则关闭)',
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _aiModelCtrl,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            helperText:
                                '例如: gpt-3.5-turbo, deepseek-chat',
                            prefixIcon:
                                Icon(Icons.model_training_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _aiApiKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            prefixIcon: Icon(Icons.key),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _aiPromptCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Prompt 模板',
                            helperText:
                                // ignore: lines_longer_than_80_chars
                                '变量: \${phrase}, \${immediateContext}, \${contextStr}\n留空使用默认模板',
                            prefixIcon:
                                Icon(Icons.text_snippet_outlined),
                          ),
                          maxLines: 6,
                          minLines: 3,
                          style: const TextStyle(
                              fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Cache ────────────────────────────────────────────────────
                _SectionHeader(title: '存储', icon: Icons.storage_outlined),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.audio_file_outlined),
                    title: const Text('音频缓存'),
                    subtitle: Text(_formatBytes(_cacheBytes)),
                    trailing: TextButton(
                      onPressed: _clearCache,
                      child: const Text('清除', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Logs ─────────────────────────────────────────────────────
                _SectionHeader(title: '调试', icon: Icons.bug_report_outlined),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('AI 解析记录'),
                        subtitle: const Text('查看所有AI解析历史'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushNamed('analysis-records'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: const Text('查看日志'),
                        subtitle: const Text('查看应用运行日志'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushNamed('log-viewer'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.share_outlined),
                        title: const Text('分享日志文件'),
                        onTap: () async {
                          final path = AppLogger.currentLogFilePath;
                          if (path != null) {
                            await Share.shareXFiles([XFile(path)],
                                subject: 'HelpToLearn 日志');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Updates ──────────────────────────────────────────────────
                _SectionHeader(title: '更新', icon: Icons.system_update_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16),
                            const SizedBox(width: 8),
                            Text('当前版本: ${VersionService.currentVersion}'),
                          ],
                        ),
                        if (_versionResult != null) ...[
                          const SizedBox(height: 12),
                          if (_versionResult!.latestVersion != null) ...[
                            Row(
                              children: [
                                Icon(
                                  _versionResult!.hasUpdate
                                      ? Icons.new_releases_outlined
                                      : Icons.check_circle_outline,
                                  size: 16,
                                  color: _versionResult!.hasUpdate
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _versionResult!.hasUpdate
                                        ? '发现新版本: ${_versionResult!.latestVersion}'
                                        : '已是最新版本',
                                    style: TextStyle(
                                      color: _versionResult!.hasUpdate
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_versionResult!.hasUpdate) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _openUrl(_versionResult!.releaseUrl),
                                  icon: const Icon(Icons.download, size: 16),
                                  label: const Text('前往下载'),
                                ),
                              ),
                            ],
                          ],
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _checkingUpdate ? null : _checkVersion,
                            icon: _checkingUpdate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: const Text('检查更新'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── About ────────────────────────────────────────────────────
                _SectionHeader(title: '关于', icon: Icons.info_outline),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('GitHub 项目'),
                    subtitle: const Text('查看源码，提交反馈'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(VersionService.githubRepo),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Account ──────────────────────────────────────────────────
                _SectionHeader(title: '账户', icon: Icons.person_outlined),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text('退出登录',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: _logout,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
