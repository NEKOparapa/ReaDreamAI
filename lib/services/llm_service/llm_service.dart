// lib/services/llm_service/llm_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/api_model.dart';
import '../../base/log/log_service.dart'; 

/// 大语言模型（LLM）服务类
class LlmService {
  // 私有构造函数，用于实现单例模式
  LlmService._();
  // 单例实例
  static final LlmService instance = LlmService._();

  // 创建一个持久化的 http 客户端，以提高性能
  final http.Client _client = http.Client();

  /// 文本补全请求
  Future<String> requestCompletion({
    String? systemPrompt,
    required List<Map<String, String>> messages,
    required ApiModel apiConfig,
  }) async {
    // 根据 apiConfig 中定义的格式，分发到不同的私有请求方法
    switch (apiConfig.format) {
      case ApiFormat.openai:
        return _requestWithOpenAiFormat(systemPrompt, messages, apiConfig);
      case ApiFormat.google:
        return _requestWithGoogleFormat(systemPrompt, messages, apiConfig);
      case ApiFormat.anthropic:
        return _requestWithAnthropicFormat(systemPrompt, messages, apiConfig);
      case ApiFormat.none:
        throw UnimplementedError('未实现的 API 格式: ${apiConfig.format}');
    }
  }

  /// 使用 OpenAI 兼容的 API 格式发起请求。
  Future<String> _requestWithOpenAiFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    // 构造请求的 URI
    final uri = Uri.parse('${apiConfig.url}/chat/completions');
    // 构造请求头
    final headers = {
      'Authorization': 'Bearer ${apiConfig.apiKey}',
      'Content-Type': 'application/json',
    };

    // 将 systemPrompt 和 messages 组合成 OpenAI 要求的格式
    final allMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(messages);

    // 构造请求体并进行 JSON 编码
    final body = jsonEncode({
      'model': apiConfig.model,
      'messages': allMessages,
      // 可在此处添加 temperature, top_p 等更多参数
    });

    LogService.instance.info('正在使用 OpenAI 格式向 ${apiConfig.url} 发起请求...');

    try {
      // 发送 POST 请求，并设置180秒超时
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      // 检查响应状态码
      if (response.statusCode == 200) {
        // 解码响应体
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        // 检查响应结构是否正确并提取内容
        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty) {
          return responseBody['choices'][0]['message']['content'] ?? '';
        } else {
          // 响应格式错误，记录日志并抛出异常
          final errorMsg = 'LLM 响应不包含 "choices" 字段。响应体: ${response.body}';
          LogService.instance.error(errorMsg);
          throw Exception(errorMsg);
        }
      } else {
        // 请求失败，记录日志并抛出异常
        final errorMsg =
            'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }
    } catch (e, s) { // 捕获异常和堆栈跟踪
      // 2. 将 print 替换为日志系统的 error 方法
      LogService.instance.error('OpenAI 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow; // 重新抛出异常，以便上层调用者可以处理
    }
  }

  /// 使用 Google Gemini API 格式发起请求。
  Future<String> _requestWithGoogleFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    // Google API 将 API Key 作为 URL 查询参数
    final uri = Uri.parse(
        '${apiConfig.url}/models/${apiConfig.model}:generateContent?key=${apiConfig.apiKey}');
    final headers = {
      'Content-Type': 'application/json',
    };

    // Gemini API 没有独立的 system prompt 字段，需要将其内容附加到第一条 user message 前
    final processedMessages = List<Map<String, String>>.from(messages);
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      final firstUserMessageIndex =
          processedMessages.indexWhere((m) => m['role'] == 'user');
      if (firstUserMessageIndex != -1) {
        final userMessage = processedMessages[firstUserMessageIndex];
        processedMessages[firstUserMessageIndex] = {
          'role': 'user',
          'content': '$systemPrompt\n\n${userMessage['content']}',
        };
      } else {
        // 如果对话历史中没有 user message，则创建一个新的
        processedMessages.insert(
            0, {'role': 'user', 'content': systemPrompt});
      }
    }
    
    // 将标准消息格式转换为 Google Gemini 的 'contents' 格式
    final contents = processedMessages.map((msg) {
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      return {
        'role': role,
        'parts': [{'text': msg['content']}]
      };
    }).toList();


    final body = jsonEncode({'contents': contents});

    LogService.instance.info('正在使用 Google 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['candidates'] != null &&
            responseBody['candidates'].isNotEmpty) {
          // Gemini 的响应结构略有不同
          return responseBody['candidates'][0]['content']['parts'][0]['text'] ?? '';
        } else {
          final errorMsg =
              'LLM 响应不包含 "candidates" 字段。响应体: ${response.body}';
          LogService.instance.error(errorMsg);
          throw Exception(errorMsg);
        }
      } else {
        final errorMsg =
            'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }
    } catch (e, s) {
      LogService.instance.error('Google 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow;
    }
  }

  /// 使用 Anthropic Claude API 格式发起请求。
  Future<String> _requestWithAnthropicFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    final uri = Uri.parse('${apiConfig.url}/messages');
    // Anthropic API 的认证和版本信息在请求头中指定
    final headers = {
      'x-api-key': apiConfig.apiKey,
      'anthropic-version': '2023-06-01', // 官方推荐的稳定版本
      'Content-Type': 'application/json',
    };

    // 构造请求体
    final bodyMap = {
      'model': apiConfig.model,
      'messages': messages, // Anthropic 的 messages 格式与 OpenAI 兼容
      'max_tokens': 20000, // Anthropic API 要求此参数, 设置一个较高的值
    };

    // Anthropic 直接支持独立的 'system' 字段
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      bodyMap['system'] = systemPrompt;
    }

    final body = jsonEncode(bodyMap);

    LogService.instance.info('正在使用 Anthropic 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['content'] != null &&
            responseBody['content'].isNotEmpty) {
          // Anthropic 的响应结构
          return responseBody['content'][0]['text'] ?? '';
        } else {
          final errorMsg =
              'LLM 响应不包含 "content" 字段。响应体: ${response.body}';
          LogService.instance.error(errorMsg);
          throw Exception(errorMsg);
        }
      } else {
        final errorMsg =
            'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }
    } catch (e, s) {
      LogService.instance.error('Anthropic 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow;
    }
  }
}