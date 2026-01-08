// lib/base/config_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'default_configs.dart';
import 'api_model.dart';
import '../models/prompt_card_model.dart';
import '../models/tag_card_model.dart'; 
import 'rate_limiter.dart';
import 'log/log_service.dart';

// 自定义的HttpOverrides类，用于设置全局代理
class _MyHttpOverrides extends HttpOverrides {
  final String port;

  _MyHttpOverrides(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        return 'PROXY localhost:$port';
      };
  }
}

/// 配置管理服务类
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  late String _configPath;
  late String _configDirectoryPath;
  late String _appDirectoryPath;
  Map<String, dynamic> _config = {};

  final Map<String, RateLimiter> _rateLimiters = {};

  /// 初始化方法
  Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    _appDirectoryPath = directory.path; 

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    LogService().info('应用数据及配置的基础存储路径: $_appDirectoryPath');

    _configDirectoryPath = p.join(_appDirectoryPath, 'Config');
    _configPath = p.join(_configDirectoryPath, 'config.json');

    await load();
    
    // 同步并保存配置
    await _synchronizeAndSaveDefaults();
  }

  /// 应用和保存默认配置，并同步系统预设项
  Future<void> _synchronizeAndSaveDefaults() async {
    bool needsSave = false;

    // 定义需要特殊处理的预设列表键
    const List<String> presetListKeys = [
      'prompt_cards',
      'drawing_style_tags',
      'drawing_negative_tags',
      'drawing_other_tags',
      'drawing_character_cards',
      'writing_background_cards',
      'writing_style_cards',
    ];

    // 第一个循环处理所有非列表的默认配置项
    for (final entry in appDefaultConfigs.entries) {
      if (!presetListKeys.contains(entry.key) && !_config.containsKey(entry.key)) {
        _config[entry.key] = entry.value;
        needsSave = true;
      }
    }

    // 处理那些需要特殊合并逻辑的预设列表
    for (final key in presetListKeys) {
      final defaultList = List<Map<String, dynamic>>.from(appDefaultConfigs[key] as List? ?? []);
      final userList = List<Map<String, dynamic>>.from(getSetting<List<dynamic>>(key, []).map((e) => e as Map<String, dynamic>));

      final mergedList = _mergePresetLists(userList: userList, defaultList: defaultList);

      if (jsonEncode(mergedList) != jsonEncode(userList)) {
        _config[key] = mergedList;
        needsSave = true;
      }
    }

    if (needsSave) {
      print("配置已更新，正在保存...");
      await save();
    }
  }

  /// 合并预设列表的辅助函数
  List<Map<String, dynamic>> _mergePresetLists({
    required List<Map<String, dynamic>> userList,
    required List<Map<String, dynamic>> defaultList,
  }) {
    // 筛选出用户自定义的项（非系统预设）
    final userCustomItems = userList.where((item) => item['isSystemPreset'] != true).toList();
    final List<Map<String, dynamic>> mergedList = List.from(defaultList);
    // 将用户自定义的项添加回去
    mergedList.addAll(userCustomItems);
    return mergedList;
  }
  
  // 根据配置文件应用或清除全局HTTP代理
  void applyHttpProxy() {
    final bool isProxyEnabled = getSetting<bool>('proxy_enabled', false);
    final String proxyPort = getSetting<String>('proxy_port', '7890');

    if (isProxyEnabled && proxyPort.isNotEmpty) {
      HttpOverrides.global = _MyHttpOverrides(proxyPort);
      LogService().info('HTTP网络代理已启用，端口: $proxyPort');
    } else {
      HttpOverrides.global = null;
      LogService().info('HTTP网络代理已关闭');
    }
  }
  
  /// 统一的应用支持目录路径的公共访问器
  String getAppDirectoryPath() {
    if (_appDirectoryPath.isEmpty) {
      throw Exception("ConfigService尚未初始化！请在应用启动时调用init()。");
    }
    return _appDirectoryPath;
  }

  /// 获取配置文件夹路径的公共访问器
  String getConfigDirectoryPath() {
    if (_configDirectoryPath.isEmpty) {
      throw Exception("ConfigService尚未初始化！请在应用启动时调用init()。");
    }
    return _configDirectoryPath;
  }
  
  /// 返回包含 character, image, video 子文件夹路径的 Map (旧工作台用)
  Future<Map<String, Directory>> getOrCreateWorkbenchDirs() async {
    final configDir = Directory(getConfigDirectoryPath());
    final workbenchDir = Directory(p.join(configDir.path, 'Workbench'));
    
    final characterDir = Directory(p.join(workbenchDir.path, 'character'));
    final imageDir = Directory(p.join(workbenchDir.path, 'Image'));
    final videoDir = Directory(p.join(workbenchDir.path, 'video'));
    
    // 确保所有文件夹都存在
    for (final dir in [characterDir, imageDir, videoDir]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    
    return {
      'character': characterDir,
      'image': imageDir,
      'video': videoDir,
    };
  }

  /// 获取或创建 游戏舞台(GameWorkbench) 专用目录
  Future<Map<String, Directory>> getOrCreateGameWorkbenchDirs() async {
    final configDir = Directory(getConfigDirectoryPath());
    final gameWorkbenchDir = Directory(p.join(configDir.path, 'GameWorkbench'));

    // 1. 角色文件夹
    final characterDir = Directory(p.join(gameWorkbenchDir.path, 'character'));
    
    // 2. 场景文件夹
    final sceneBaseDir = Directory(p.join(gameWorkbenchDir.path, 'scene'));
    final sceneImageDir = Directory(p.join(sceneBaseDir.path, 'image'));
    final sceneMusicDir = Directory(p.join(sceneBaseDir.path, 'music'));

    // 创建目录
    for (final dir in [characterDir, sceneImageDir, sceneMusicDir]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    return {
      'character': characterDir,
      'scene_image': sceneImageDir,
      'scene_music': sceneMusicDir,
    };
  }

  // 清空工作台媒体文件，清空Workbench下的 image, video, character 文件夹内容
  Future<void> clearWorkbenchMedia() async {
    final logger = LogService.instance;
    logger.info("正在清空工作台媒体文件...");
    try {
      final workbenchDirs = await getOrCreateWorkbenchDirs();
      final imageDir = workbenchDirs['image']!;
      final videoDir = workbenchDirs['video']!;
      final characterDir = workbenchDirs['character']!;

      Future<void> _clearDirectory(Directory dir) async {
        if (await dir.exists()) {
          final entities = dir.list();
          await for (final entity in entities) {
            try {
              await entity.delete(recursive: true);
            } catch (e) {
              logger.error("删除文件失败: ${entity.path}", e);
            }
          }
          logger.info("已清空目录: ${dir.path}");
        }
      }

      await _clearDirectory(imageDir);
      await _clearDirectory(videoDir);
      await _clearDirectory(characterDir);
      logger.success("工作台媒体文件已清空。");
    } catch (e, s) {
      logger.error("清空工作台媒体文件时发生错误", e, s);
    }
  }

  /// 加载配置文件方法
  Future<void> load() async {
    final file = File(_configPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          _config = json.decode(content);
        } else {
          _config = {};
        }
      } catch (e) {
        LogService().info('Error loading config file: $e');
        _config = {};
      }
    } else {
      _config = {};
    }
  }

  /// 保存全部配置文件方法
  Future<void> save() async {
    final file = File(_configPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    final content = encoder.convert(_config);
    await file.writeAsString(content);
  }

  /// 修改/获取设置项的方法
  Future<void> modifySetting<T>(String key, T value) async {
    _config[key] = value;
    await save();
  }

  /// 获取设置项的方法
  T getSetting<T>(String key, T defaultValue) {
    return _config[key] as T? ?? defaultValue;
  }

  // 为指定的API配置获取或创建速率限制器
  RateLimiter getRateLimiterForApi(ApiModel api) {
    if (_rateLimiters.containsKey(api.id)) {
      return _rateLimiters[api.id]!;
    } else {
      LogService().info("为 API '${api.name}' (ID: ${api.id}) 创建新的速率限制器 (RPM: ${api.rpm})");
      final newLimiter = RateLimiter(rpm: api.rpm);
      _rateLimiters[api.id] = newLimiter;
      return newLimiter;
    }
  }

  /// 获取正在激活的语言接口
  ApiModel getActiveLanguageApi() {
    return _getActiveApi('activeLanguageApiId', 'languageApis', '语言接口');
  }

  /// 根据ID获取特定的语言接口
  ApiModel getLanguageApiById(String? apiId) {
    if (apiId == null) {
      return getActiveLanguageApi();
    }
    final apisJson = getSetting<List>('languageApis', []);
    final apis = apisJson.map((json) => ApiModel.fromJson(json as Map<String, dynamic>)).toList();
    try {
      return apis.firstWhere((api) => api.id == apiId);
    } catch (e) {
      LogService.instance.warn("未找到ID为 '$apiId' 的语言接口，已回退到当前激活的接口。");
      return getActiveLanguageApi();
    }
  }

  /// 获取正在激活的绘画接口
  ApiModel getActiveDrawingApi() {
    return _getActiveApi('activeDrawingApiId', 'drawingApis', '绘画接口');
  }

  /// 获取正在激活的视频接口
  ApiModel getActiveVideoApi() {
    return _getActiveApi('activeVideoApiId', 'videoApis', '视频接口');
  }
  
  /// 获取正在激活的音乐接口
  ApiModel getActiveMusicApi() {
    return _getActiveApi('activeMusicApiId', 'musicApis', '音乐接口');
  }

  /// 通用的获取激活API的逻辑
  ApiModel _getActiveApi(String activeIdKey, String apiListKey, String apiTypeName) {
    final activeId = getSetting<String?>(activeIdKey, null);
    if (activeId == null) {
      throw Exception("没有激活的$apiTypeName。请在设置中配置一个。");
    }

    final apisJson = getSetting<List>(apiListKey, []);
    final apis = apisJson.map((json) => ApiModel.fromJson(json as Map<String, dynamic>)).toList();

    try {
      return apis.firstWhere((api) => api.id == activeId);
    } catch (e) {
      throw Exception("未找到激活的$apiTypeName，ID: '$activeId'。请在设置中重新选择一个。");
    }
  }
  
  /// 根据标签列表键和激活ID键获取激活标签的内容
  String getActiveTagContent(String listKey, String activeIdKey) {
    final activeId = getSetting<String?>(activeIdKey, null);
    if (activeId == null) return '';

    final tagsJson = getSetting<List<dynamic>>(listKey, []);
    final tags = tagsJson.map((json) => TagCard.fromJson(json as Map<String, dynamic>)).toList();
    
    try {
      final activeTag = tags.firstWhere((tag) => tag.id == activeId);
      return activeTag.content;
    } catch (e) {
      return '';
    }
  }

  /// 根据提示词列表键和激活ID键获取激活提示词卡片的内容
  String getActivePromptCardContent() {
    final activeId = getSetting<String?>('active_prompt_card_id', null);
    if (activeId == null) return '';

    final cardsJson = getSetting<List<dynamic>>('prompt_cards', []);
    final cards = cardsJson.map((json) => PromptCard.fromJson(json as Map<String, dynamic>)).toList();
    
    try {
      final activeCard = cards.firstWhere((card) => card.id == activeId);
      return activeCard.content;
    } catch (e) {
      return '';
    }
  }
}