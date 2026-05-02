# AnkiDroid 集成与 flutter_ankidroid 踩坑记录

本文档记录了在 Flutter App 中集成 AnkiDroid（推送带有音频的卡片）时遇到的系列连环问题及解决方案。
由于第三方插件 `flutter_ankidroid: ^0.8.1` 存在诸多隐蔽的 Bug 和文档缺失，特此记录以备查阅。

## 1. 卡片字段 (Fields) 数量与 Anki 模板必须严格对齐

**现象：**
App 调用 `_anki!.addNote(...)` 直接抛出错误或静默失败，AnkiDroid 中没有成功创建卡片。

**原因：**
使用 AnkiConnect (Web端) 时，可以通过键值对 (如 `{"正面": "...", "背面": "..."}`) 推送字段。但在 App 端使用的是 AnkiDroid 的 ContentProvider API，它**只接受一个字符串数组 (List)**，并严格按照卡片模板中定义的字段顺序进行填充。如果数组长度与模板字段数量不符，写入就会失败。

**解决方案：**
在 `AnkiService.dart` 中，将原文、译文、在线链接拼装成一个单一的 HTML 字符串作为“正面”，将音频标签作为“背面”。确保最终传入的 `fields` 数组长度正好为 2（对应模板的正面和背面）。

## 2. 必须明确添加文件后缀名

**现象：**
卡片成功创建，但背面提示 `[sound:htl_seg_xxx]`。在 AnkiDroid 点击播放时，提示“加载音频失败”。

**原因：**
通过 `_anki!.addMedia` 推送音频字节时，如果传入的 `preferredName` 缺少 `.mp3` 等扩展名，AnkiDroid 底层在保存该文件时将不带扩展名。即使 Anki 写入了对应的 `[sound:...]` 标签，由于没有 `.mp3` 后缀，AnkiDroid 播放器无法识别媒体格式而报错。

**解决方案：**
调用 `_anki!.addMedia(bytes, 'htl_seg_${segment.id}.mp3', 'audio')`，确保传入的文件名自带 `.mp3` 后缀。

## 3. 🚨 插件源码级灾难 Bug：addMedia 方法调用错误

**现象：**
即使用上了 `.mp3` 后缀，并且正常获取了本地的音频字节，上传时没有任何反应，音频始终无法存入 Anki 的 `collection.media` 目录。

**原因：**
在 `flutter_ankidroid` (v0.8.1) 插件包内部源码中，作者在编写 Dart 层的 `addMedia` 函数时，复制粘贴了 `addNotes` 函数的模板，却**忘记修改 Channel 发送的指令名称**。
```dart
// 插件内 flutter_ankidroid.dart 源码中的错误：
Future<Result<String>> addMedia(Uint8List bytes, String preferredName, String mimeType) async {
  ...
  _ankiPort.send({
    'functionName': 'addNotes', // <--- 致命错误！这里本应是 'addMedia'
    ...
```
导致该函数向原生代码发送了无法解析的参数，引发异常。

**解决方案：**
目前已直接修改本地 `.pub-cache` 缓存中的 `flutter_ankidroid.dart` 源码。
如果后续在 CI/CD 或其他机器上部署，需要：
1. 提交 PR 修复原仓库，或 Fork 出来并修改项目 `pubspec.yaml`，使用 Git 引用你的修复版本。
2. 或在 `pubspec.yaml` 中配置 `dependency_overrides` 指定一个包含该修复的本地包路径。

## 4. 缺失 FileProvider 导致的隐式崩溃

**现象：**
修复了 `addMedia` 指令名后，发现代码运行到上传阶段时，Flutter 后台 Isolate 会直接崩溃退出，或者日志打印异常。

**原因：**
插件 `flutter_ankidroid` 在原生 (Kotlin) 层调用 `addMediaFromUri` 时，创建了一个临时文件并试图使用 Android 的 `FileProvider` 来安全地将该文件共享给 AnkiDroid 应用：
```kotlin
val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", tempfile)
context.grantUriPermission("com.ichi2.anki", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
```
但插件作者的文档并没有提醒开发者需要配置 `FileProvider`。因为我们自己的主项目中没有配置 `<provider>`，导致原生抛出 `IllegalArgumentException`，进程直接崩溃。

**解决方案：**
1. 在 `android/app/src/main/res/xml/file_paths.xml` 中创建文件映射：
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <paths>
       <files-path name="files" path="." />
   </paths>
   ```
2. 在 `AndroidManifest.xml` 中手动声明 `FileProvider`：
   ```xml
   <provider
       android:name="androidx.core.content.FileProvider"
       android:authorities="${applicationId}.fileprovider"
       android:exported="false"
       android:grantUriPermissions="true">
       <meta-data
           android:name="android.support.FILE_PROVIDER_PATHS"
           android:resource="@xml/file_paths" />
   </provider>
   ```
配置完成后，App 终于可以将音频顺利传递给 AnkiDroid 了。
