import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api/materials_api.dart';
import '../../core/logging/app_logger.dart';

enum _AddMode { url, text, upload }

class AddMaterialPage extends ConsumerStatefulWidget {
  final String? initialUrl;
  final String? initialText;
  final bool temporary;
  const AddMaterialPage({
    super.key,
    this.initialUrl,
    this.initialText,
    this.temporary = false,
  });

  @override
  ConsumerState<AddMaterialPage> createState() => _AddMaterialPageState();
}

class _AddMaterialPageState extends ConsumerState<AddMaterialPage> {
  _AddMode _mode = _AddMode.url;
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  String _language = 'en';
  bool _loading = false;
  String? _error;
  String? _pickedFilePath;
  String? _pickedFileName;

  bool get _isTemporary => widget.temporary;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlCtrl.text = widget.initialUrl!;
    }
    if (widget.initialText != null) {
      _mode = _AddMode.text;
      _textCtrl.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final mt = _isTemporary ? 'temporary' : 'main';

    try {
      switch (_mode) {
        case _AddMode.url:
          final url = _urlCtrl.text.trim();
          if (url.isEmpty) throw Exception('请输入URL');
          final isArticle = !_isMediaUrl(url);
          AppLogger.info('Adding material URL: $url (article=$isArticle temporary=$_isTemporary)',
              tag: 'AddMaterial');
          if (isArticle) {
            await materialsApi.importUrlArticle(
                url: url,
                title: _titleCtrl.text.isEmpty ? null : _titleCtrl.text,
                language: _language,
                materialType: mt);
          } else {
            await materialsApi.importUrlMedia(
                url: url,
                title: _titleCtrl.text.isEmpty ? null : _titleCtrl.text,
                language: _language,
                materialType: mt);
          }
          break;

        case _AddMode.text:
          final text = _textCtrl.text.trim();
          final title = _titleCtrl.text.trim();
          if (text.isEmpty) throw Exception('请输入文本内容');
          if (_isTemporary) {
            AppLogger.info('Adding text snippet: "$title"', tag: 'AddMaterial');
            await materialsApi.importTextSnippet(
                text: text,
                title: title.isEmpty ? null : title,
                language: _language);
          } else {
            if (title.isEmpty) throw Exception('请输入标题');
            AppLogger.info('Adding text material: "$title"', tag: 'AddMaterial');
            await materialsApi.importText(
                text: text, title: title, language: _language, materialType: mt);
          }
          break;

        case _AddMode.upload:
          if (_pickedFilePath == null) throw Exception('请选择文件');
          final title = _titleCtrl.text.trim().isEmpty
              ? _pickedFileName!
              : _titleCtrl.text.trim();
          AppLogger.info('Uploading file: $_pickedFileName', tag: 'AddMaterial');
          await materialsApi.uploadFile(
            filePath: _pickedFilePath!,
            fileName: _pickedFileName!,
            title: title,
            language: _language,
            materialType: mt,
          );
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isTemporary ? '✅ 临时素材已提交，正在处理...' : '✅ 素材已提交，正在处理...'),
              duration: const Duration(seconds: 3)),
        );
        context.go(_isTemporary ? '/temporary-materials' : '/materials');
      }
    } catch (e, st) {
      AppLogger.error('Add material failed',
          tag: 'AddMaterial', error: e, stackTrace: st);
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _loading = false;
      });
    }
  }

  bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('bilibili.com') ||
        lower.contains('.mp4') ||
        lower.contains('.mp3') ||
        lower.contains('.m4a');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mp3', 'wav', 'm4a', 'mkv', 'webm', 'aac'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFilePath = result.files.single.path;
        _pickedFileName = result.files.single.name;
        if (_titleCtrl.text.isEmpty) {
          _titleCtrl.text = result.files.single.name.split('.').first;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isTemporary ? '添加临时素材' : '添加素材')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode selector
            SegmentedButton<_AddMode>(
              segments: const [
                ButtonSegment(
                    value: _AddMode.url,
                    icon: Icon(Icons.link, size: 18),
                    label: Text('URL')),
                ButtonSegment(
                    value: _AddMode.text,
                    icon: Icon(Icons.text_fields, size: 18),
                    label: Text('文本')),
                ButtonSegment(
                    value: _AddMode.upload,
                    icon: Icon(Icons.upload_file, size: 18),
                    label: Text('上传')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 24),

            // Language selector
            DropdownButtonFormField<String>(
              value: _language,
              decoration: const InputDecoration(
                  labelText: '语言', prefixIcon: Icon(Icons.language)),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'zh', child: Text('中文')),
                DropdownMenuItem(value: 'ja', child: Text('日本語')),
                DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                DropdownMenuItem(value: 'fr', child: Text('Français')),
              ],
              onChanged: (v) => setState(() => _language = v!),
            ),
            const SizedBox(height: 16),

            // Mode-specific fields
            if (_mode == _AddMode.url) ...[
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL (YouTube / 文章链接)',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题（可选，不填则自动提取）',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
            ],

            if (_mode == _AddMode.text) ...[
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _textCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '文本内容',
                  alignLabelWithHint: true,
                ),
              ),
            ],

            if (_mode == _AddMode.upload) ...[
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _pickedFileName != null
                            ? Colors.green.withOpacity(0.5)
                            : const Color(0xFF3A3A5E)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pickedFileName != null
                            ? Icons.audio_file
                            : Icons.upload_file,
                        color: _pickedFileName != null
                            ? Colors.green
                            : Colors.white38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _pickedFileName ?? '点击选择音视频文件',
                          style: TextStyle(
                              color: _pickedFileName != null
                                  ? Colors.white
                                  : Colors.white38),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ],

            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: const Text('提交'),
            ),
          ],
        ),
      ),
    );
  }
}
