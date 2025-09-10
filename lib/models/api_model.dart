// lib/models/api_model.dart

import 'package:uuid/uuid.dart';

// 接口平台枚举
enum ApiProvider {
  // 语言模型
  openai,
  groq,
  deepseek,
  google,
  anthropic,
  // 绘画模型
  volcengine,
  kling,
  liblib,
  comfyui,
  // 通用
  custom,
}

//接口格式枚举
enum ApiFormat {
  openai,
  google,
  anthropic,
}

class ApiModel {
  String id;
  String name;
  String url;
  String apiKey;
  String? accessKey; 
  String? secretKey;  
  String model;   // 模型名称
  ApiProvider provider;   // 接口平台
  ApiFormat format;      // 接口格式
  int? concurrencyLimit; // 并发数限制
  int? rpm;              // 每分钟请求数 (Requests Per Minute)
  int? qps;              // 每秒查询数 (Queries Per Second)

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
    this.qps,
  });


  // 工厂方法创建一个新的 ApiModel 实例
  factory ApiModel.create(String name) {
    return ApiModel(
      id: const Uuid().v4(),
      name: name,
      url: 'https://api.openai.com/v1',
      provider: ApiProvider.openai,
      format: ApiFormat.openai,
      model: 'gpt-4o-mini',
      concurrencyLimit: 2, // 默认并发数为 2
      rpm: 30,             // 默认每分钟 30 次请求
    );
  }


  // 工厂方法创建一个新的绘画 ApiModel 实例
  factory ApiModel.createDrawing(String name) {
    return ApiModel(
      id: const Uuid().v4(),
      name: name,
      url: 'https://ark.cn-beijing.volces.com/api/v3', // 使用一个更常见的默认值
      provider: ApiProvider.volcengine,
      format: ApiFormat.openai,
      model: 'sdxl',
      concurrencyLimit: 1, // 默认并发数为 1
      qps: 1,              // 默认每秒 1 次请求
    );
  }

  // 从JSON解析ApiModel对象
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
      // 新增：从JSON解析速率限制字段
      concurrencyLimit: json['concurrencyLimit'],
      rpm: json['rpm'],
      qps: json['qps'],
    );
  }

  // 将ApiModel对象序列化为JSON
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
      'qps': qps,
    };
  }
}