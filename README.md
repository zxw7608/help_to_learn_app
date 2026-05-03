# Help to Learn App (听读学习助手)

一个基于 **Flutter** 开发的高颜值、高性能英语学习辅助客户端，专为精听、阅读和 Anki 深度学习设计。本应用与 [help_to_learn 后端](file:///c:/Users/User0/Desktop/help_to_learn) 完美协同，支持多源资料导入、流式段落音频播放、本地缓存管理以及 AnkiDroid 深度制卡整合，帮助你高效吸收、反复磨练英语技能。

---

## 🌟 核心功能

- **📚 英语学习资料库**
  - 支持多源导入：本地文件、YouTube/Bilibili 视频链接、网页文章或纯文本。
  - 按列表与分类轻松管理你的所有学习材料。

- **🎧 精准分句音频播放器**
  - **基于 `just_audio` 构建**，支持高精度音频播放。
  - **流式段落音频同步**：精准对应文章句子。
  - **播放控制模式**：支持段落单曲循环、列表连续播放等高级模式。
  - **智能本地缓存**：基于 `CacheService` 自动缓存网络音频资源，在离线或弱网环境下依然能流畅听读。

- **📇 AnkiDroid 原生制卡集成**
  - 内置强大的 `AnkiService`，可通过 Android Native API 直接与本地 AnkiDroid 通信。
  - 支持一键将当前句子、音频片段、原文/翻译同步推送到本地 AnkiDroid 制作成记忆卡片，实现听力词汇的深度记忆。

- **🔐 账号与同步**
  - 支持 JWT 用户认证与服务器端多设备同步。
  - 动态切换 API 基础路径，方便在多套后端环境下灵活切换。

- **📂 高级设置与日志**
  - 内置基于 `FileLogOutput` 的文件持久化日志系统。
  - 支持在应用内通过日志浏览器直接查看及导出运行日志，方便排查与反馈问题。

---

## 🏗️ 架构与技术栈

本应用遵循现代 Flutter 模块化与声明式架构（Feature-first Architecture）：

- **跨平台框架**: [Flutter SDK](https://flutter.dev) (`>=3.3.0 <4.0.0`)
- **状态管理**: `flutter_riverpod` & `riverpod_annotation` (声明式、响应式状态管理)
- **路由导航**: `go_router` (声明式路由)
- **网络通信**: `dio` & `dio_cache_interceptor`
- **本地存储**: `shared_preferences` & `flutter_secure_storage`
- **音频服务**: `just_audio`
- **原生桥接**: `flutter_ankidroid`
- **日志诊断**: `logger` (通过文件/内存自定义输出)

---

## 📂 项目目录结构

```
├── lib/
│   ├── app.dart              — 应用主入口 Widget
│   ├── main.dart             — 程序启动入口，初始化本地服务与 Riverpod Provider Scope
│   ├── core/                 — 核心基础模块
│   │   ├── api/              — ApiClient 与 JWT 鉴权拦截器
│   │   ├── logging/          — 文件与内存日志记录器 (AppLogger)
│   │   ├── models/           — 实体定义 (Material, PlaylistState 等)
│   │   ├── router/           — GoRouter 路由映射与底部导航
│   │   ├── services/         — 核心业务 (Anki 适配、音频管理、本地缓存)
│   │   └── theme/            — 应用视觉主题与调色盘
│   └── features/             — 业务功能模块
│       ├── auth/             — 登录/注册模块
│       ├── materials/        — 资料列表、分类查看、资料导入页面
│       ├── player/           — 高级音频精听播放器与同步分句视图
│       ├── playlist/         — 正在播放列表与迷你播放器
│       └── settings/         — API 配置、用户信息、文件日志查看器
```

---

## 🚀 快速上手

### 1. 环境准备

- 确保你的本地开发环境已安装 **Flutter SDK** (`>=3.3.0`)。
- 如果需要使用 **AnkiDroid 同步功能**，请确保你的 Android 设备上已安装 **[AnkiDroid](https://github.com/ankidroid/Anki-Android)** 并开启了 `允许第三方应用向其添加内容` 选项。

### 2. 获取源码并运行

```bash
# 克隆仓库
git clone <repository_url>

# 安装依赖
flutter pub get

# 运行代码生成器（Riverpod, Router 等自动生成部分）
dart run build_runner build --delete-conflicting-outputs

# 启动应用
flutter run
```

---

## 📖 核心功能配置说明

### API 服务器配置
第一次启动应用后，你可以在 **登录页面** 或 **设置页面** 配置你的 API 基础路径，使其指向 `help_to_learn` 后端服务的接口地址（例如 `http://192.168.1.100:8000`）。

### Anki 深度同步设置
1. 打开 **AnkiDroid**。
2. 进入 `设置` -> `高级设置` -> 勾选 `允许第三方应用 API`。
3. 返回 **Help to Learn App**，在学习资料音频页面点击 **“推送到 Anki”**，即可将对应句子的音频和文本一键导入 AnkiDroid 的生词本中。

---

## 🤝 参与贡献

如果你在使用过程中遇到任何 Bug 或有新的 feature 想法，欢迎随时提交 **Issue** 或发起 **Pull Request**！
