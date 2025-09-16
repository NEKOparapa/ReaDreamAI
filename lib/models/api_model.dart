// lib/models/api_model.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

// 接口平台枚举 
enum ApiProvider {
  // 语言模型
  openai,
  deepseek,
  google,
  anthropic,
  // 绘画与视频模型
  volcengine,
  // 绘画模型
  kling,
  dashscope, 
  comfyui,
  // 视频模型
  bailian, // 新增：百炼
  // 通用
  custom,
}

// 接口格式枚举 
enum ApiFormat {
  openai,
  google,
  anthropic,
}

// =================================================================
// 统一的平台预设信息类
// =================================================================
class ApiPlatformPreset {
  final ApiProvider provider;
  final String name;
  final IconData icon;
  final String defaultUrl;
  final String defaultModel;
  final ApiFormat defaultFormat;
  final int defaultConcurrency;
  final int defaultRpm;

  const ApiPlatformPreset({
    required this.provider,
    required this.name,
    required this.icon,
    required this.defaultUrl,
    required this.defaultModel,
    required this.defaultFormat,
    required this.defaultConcurrency,
    required this.defaultRpm,
  });
}

// =================================================================
// 独立的语言接口平台预设列表
// =================================================================
final List<ApiPlatformPreset> languagePlatformPresets = [
  const ApiPlatformPreset(
    provider: ApiProvider.openai, name: 'OpenAI', icon: Icons.cloud_outlined, 
    defaultUrl: 'https://api.openai.com/v1', defaultModel: 'gpt-4o-mini', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 2, defaultRpm: 60
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.volcengine, name: 'VolcEngine', icon: Icons.filter_hdr_outlined, 
    // 这是火山的语言模型预设
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3', defaultModel: 'Doubao-pro-32k', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 2, defaultRpm: 60
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.deepseek, name: 'DeepSeek', icon: Icons.search, 
    defaultUrl: 'https://api.deepseek.com/v1', defaultModel: 'deepseek-chat', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 2, defaultRpm: 60
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.google, name: 'Google', icon: Icons.bubble_chart_outlined, 
    // 这是谷歌的语言模型预设
    defaultUrl: 'https://generativelanguage.googleapis.com/v1beta', defaultModel: 'gemini-1.5-flash-latest', 
    defaultFormat: ApiFormat.google, defaultConcurrency: 2, defaultRpm: 60
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.anthropic, name: 'Anthropic', icon: Icons.hub_outlined, 
    defaultUrl: 'https://api.anthropic.com/v1', defaultModel: 'claude-3-haiku-20240307', 
    defaultFormat: ApiFormat.anthropic, defaultConcurrency: 2, defaultRpm: 60
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.custom, name: '自定义', icon: Icons.settings_ethernet, 
    defaultUrl: '', defaultModel: '', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 2, defaultRpm: 60
  ),
];

// =================================================================
// 独立的绘画接口平台预设列表
// =================================================================
final List<ApiPlatformPreset> drawingPlatformPresets = [
  const ApiPlatformPreset(
    provider: ApiProvider.volcengine, name: 'Volcengine', icon: Icons.filter_hdr_outlined,
    // 这是火山的绘画模型预设
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3', defaultModel: 'sdxl-lightning', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 30
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.google, name: 'Google', icon: Icons.bubble_chart_outlined, 
    // 这是谷歌的绘画模型预设
    defaultUrl: 'https://generativelanguage.googleapis.com/v1beta', defaultModel: 'gemini-1.5-pro-latest', 
    defaultFormat: ApiFormat.google, defaultConcurrency: 1, defaultRpm: 30
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.dashscope, name: '千问', icon: Icons.bolt_outlined, 
    defaultUrl: 'https://dashscope.aliyuncs.com/api/v1', defaultModel: 'wanx-v1', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 30
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.kling, name: 'Kling', icon: Icons.movie_filter_outlined, 
    defaultUrl: 'https://api-beijing.klingai.com', defaultModel: 'kling-v1', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 5
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.comfyui, name: 'ComfyUI', icon: Icons.account_tree_outlined, 
    defaultUrl: 'http://127.0.0.1:8188', defaultModel: '', // ComfyUI模型在工作流中定义
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 30
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.custom, name: '自定义', icon: Icons.settings_ethernet, 
    defaultUrl: '', defaultModel: '', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 30
  ),
];

// =================================================================
// 独立的视频接口平台预设列表
// =================================================================
final List<ApiPlatformPreset> videoPlatformPresets = [
  const ApiPlatformPreset(
    provider: ApiProvider.bailian, name: '百炼(通义)', icon: Icons.whatshot_outlined, 
    defaultUrl: 'https://dashscope.aliyuncs.com/api/v1', 
    defaultModel: 'wan2.2-t2v-plus', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 5
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.volcengine, name: '火山', icon: Icons.filter_hdr_outlined,
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3', 
    defaultModel: 'doubao-seedance-1-0-pro-250528', // 使用文档中的示例模型
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 5
  ),
  const ApiPlatformPreset(
    provider: ApiProvider.custom, name: '自定义', icon: Icons.settings_ethernet, 
    defaultUrl: '', defaultModel: '', 
    defaultFormat: ApiFormat.openai, defaultConcurrency: 1, defaultRpm: 5
  ),
];


// ApiModel 类
class ApiModel {
  String id;
  String name;
  String url;
  String apiKey;
  String? accessKey; 
  String? secretKey;  
  String model;
  ApiProvider provider;
  ApiFormat format;
  int? concurrencyLimit;
  int? rpm;

  ApiModel({
    required this.id,
    required this.name,
    required this.url,
    this.apiKey = '',
    this.accessKey,
    this.secretKey,
    this.model = 'default',
    this.provider = ApiProvider.openai,
    this.format = ApiFormat.openai,
    this.concurrencyLimit,
    this.rpm,
  });

  factory ApiModel.create(String name) {
    // 直接从独立的语言列表中查找默认预设 (OpenAI)
    final preset = languagePlatformPresets.firstWhere((p) => p.provider == ApiProvider.openai);
    return ApiModel(
      id: const Uuid().v4(),
      name: name,
      url: preset.defaultUrl,
      provider: preset.provider,
      format: preset.defaultFormat,
      model: preset.defaultModel,
      concurrencyLimit: preset.defaultConcurrency,
      rpm: preset.defaultRpm,
    );
  }

  factory ApiModel.createDrawing(String name) {
    // 直接从独立的绘画列表中查找默认预设 (Volcengine)
    final preset = drawingPlatformPresets.firstWhere((p) => p.provider == ApiProvider.volcengine);
    return ApiModel(
      id: const Uuid().v4(),
      name: name,
      url: preset.defaultUrl,
      provider: preset.provider,
      format: preset.defaultFormat,
      model: preset.defaultModel,
      concurrencyLimit: preset.defaultConcurrency,
      rpm: preset.defaultRpm,
    );
  }

  // 新增：创建视频接口的工厂方法
  factory ApiModel.createVideo(String name) {
    // 从视频列表中查找默认预设 (百炼)
    final preset = videoPlatformPresets.firstWhere((p) => p.provider == ApiProvider.bailian);
    return ApiModel(
      id: const Uuid().v4(),
      name: name,
      url: preset.defaultUrl,
      provider: preset.provider,
      format: preset.defaultFormat,
      model: preset.defaultModel,
      concurrencyLimit: preset.defaultConcurrency,
      rpm: preset.defaultRpm,
    );
  }

  factory ApiModel.fromJson(Map<String, dynamic> json) {
    return ApiModel(
      id: json['id'],
      name: json['name'],
      url: json['url'],
      apiKey: json['apiKey'] ?? '',
      accessKey: json['accessKey'],
      secretKey: json['secretKey'],
      model: json['model'] ?? 'default',
      provider: ApiProvider.values.firstWhere(
        (e) => e.name == json['provider'],
        orElse: () => json['isCustomUrl'] == true ? ApiProvider.custom : ApiProvider.openai
      ),
      format: ApiFormat.values.firstWhere(
        (e) => e.name == json['format'],
        orElse: () => ApiFormat.openai
      ),
      concurrencyLimit: json['concurrencyLimit'],
      rpm: json['rpm'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'apiKey': apiKey,
      'accessKey': accessKey,
      'secretKey': secretKey,
      'model': model,
      'provider': provider.name,
      'format': format.name,
      'concurrencyLimit': concurrencyLimit,
      'rpm': rpm,
    };
  }
}