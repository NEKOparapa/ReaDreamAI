// lib/base/config_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'default_configs.dart';
import '../models/api_model.dart';
import '../models/prompt_card_model.dart';
import '../models/tag_card_model.dart'; 
import 'rate_limiter.dart';

// 自定义的HttpOverrides类，用于设置全局代理
class _MyHttpOverrides extends HttpOverrides {
  final String port;

  _MyHttpOverrides(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // 将所有HTTP和HTTPS流量都指向本地代理
        // 假设代理在 localhost 上
        return 'PROXY localhost:$port';
      };
  }
}


/// 配置管理服务类
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  late String _configPath; // 配置文件的完整路径
  late String _appDirectoryPath; // 统一的应用支持目录路径
  Map<String, dynamic> _config = {}; // 内存中的配置数据

  final Map<String, RateLimiter> _rateLimiters = {};

  /// 初始化方法
  Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    _appDirectoryPath = directory.path; 

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    print('应用数据基础存储路径: $_appDirectoryPath');
    
    _configPath = p.join(_appDirectoryPath, 'config.json');
    
    await load();
    
    await _applyAndSaveDefaults();
  }
  
  /// 根据配置文件应用或清除全局HTTP代理
  void applyHttpProxy() {
    final bool isProxyEnabled = getSetting<bool>('proxy_enabled', false);
    final String proxyPort = getSetting<String>('proxy_port', '7890');

    if (isProxyEnabled && proxyPort.isNotEmpty) {
      // 启用代理
      HttpOverrides.global = _MyHttpOverrides(proxyPort);
      print('HTTP网络代理已启用，端口: $proxyPort');
    } else {
      // 禁用代理
      HttpOverrides.global = null;
      print('HTTP网络代理已关闭');
    }
  }


  /// 统一的应用支持目录路径的公共访问器
  String getAppDirectoryPath() {

    if (_appDirectoryPath.isEmpty) {
      throw Exception("ConfigService尚未初始化！请在应用启动时调用init()。");
    }
    return _appDirectoryPath;
  }

  /// 应用和保存默认配置
  Future<void> _applyAndSaveDefaults() async {

    bool needsSave = false;
    for (final entry in appDefaultConfigs.entries) {
      if (!_config.containsKey(entry.key)) {
        _config[entry.key] = entry.value;
        needsSave = true;
      }
    }
    if (needsSave) {
      await save();
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
        print('Error loading config file: $e');
        _config = {};
      }
    } else {
      _config = {};
    }
  }

  /// 保存全部配置文件方法
  Future<void> save() async {
    final file = File(_configPath);
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
      // 如果已存在，直接返回
      return _rateLimiters[api.id]!;
    } else {
      // 如果不存在，则创建一个新的，并存入缓存
      // 已修改：更新日志和 RateLimiter 构造函数
      print("为 API '${api.name}' (ID: ${api.id}) 创建新的速率限制器 (RPM: ${api.rpm})");
      final newLimiter = RateLimiter(rpm: api.rpm);
      _rateLimiters[api.id] = newLimiter;
      return newLimiter;
    }
  }

  /// 获取正在激活的语言接口
  ApiModel getActiveLanguageApi() {
    return _getActiveApi(
      'activeLanguageApiId',
      'languageApis',
      '语言接口',
    );
  }

  /// 获取正在激活的绘画接口
  ApiModel getActiveDrawingApi() {
    return _getActiveApi(
      'activeDrawingApiId',
      'drawingApis',
      '绘画接口',
    );
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
      return ''; // 没找到或出错则返回空
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
      return ''; // 没找到或出错则返回空
    }
  }
}