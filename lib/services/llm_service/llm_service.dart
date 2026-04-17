// lib/services/llm_service/llm_service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../base/api_model.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';

/// 大语言模型（LLM）请求服务。
class LlmService {
  LlmService._();

  static final LlmService instance = LlmService._();

  final ConfigService _configService = ConfigService();
  final http.Client _client = http.Client();

  Future<String> requestCompletion({
    String? systemPrompt,
    required List<Map<String, String>> messages,
    required ApiModel apiConfig,
  }) async {
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

  Future<String> _requestWithOpenAiFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    final uri = Uri.parse('${apiConfig.url}/chat/completions');
    final headers = {
      'Authorization': 'Bearer ${apiConfig.apiKey}',
      'Content-Type': 'application/json',
    };

    final processedMessages = List<Map<String, String>>.from(messages);
    if (_shouldRemoveLastAssistantMessage(processedMessages, apiConfig)) {
      processedMessages.removeLast();
    }

    final allMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(processedMessages);

    final body = jsonEncode({
      'model': apiConfig.model,
      'messages': allMessages,
      'temperature': 1,
    });

    LogService.instance.info('正在使用 OpenAI 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 300));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty) {
          return responseBody['choices'][0]['message']['content'] ?? '';
        }

        final errorMsg = 'LLM 响应不包含 "choices" 字段。响应体: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }

      final errorMsg = 'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
      LogService.instance.error(errorMsg);
      throw Exception(errorMsg);
    } catch (e, s) {
      LogService.instance.error('OpenAI 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow;
    }
  }

  bool _shouldRemoveLastAssistantMessage(
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) {
    if (messages.isEmpty || messages.last['role'] != 'assistant') {
      return false;
    }

    if (apiConfig.model.toLowerCase().contains('deepseek')) {
      return true;
    }

    final includeLastAssistantMessage = _configService.getSetting<bool>(
      'include_last_assistant_message_in_prompt',
      true,
    );
    return !includeLastAssistantMessage;
  }

  Future<String> _requestWithGoogleFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    final uri = Uri.parse(
      '${apiConfig.url}/models/${apiConfig.model}:generateContent?key=${apiConfig.apiKey}',
    );
    final headers = {'Content-Type': 'application/json'};

    final contents = messages.map((msg) {
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      return {
        'role': role,
        'parts': [
          {'text': msg['content']},
        ],
      };
    }).toList();

    final bodyMap = <String, dynamic>{
      'contents': contents,
      'generationConfig': {'temperature': 1},
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      bodyMap['system_instruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
      };
    }

    final body = jsonEncode(bodyMap);

    LogService.instance.info('正在使用 Google 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));

        if (responseBody['error'] != null) {
          final errorMsg = 'Google API 返回错误: ${response.body}';
          LogService.instance.error(errorMsg);
          throw Exception(errorMsg);
        }

        if (responseBody['candidates'] != null &&
            responseBody['candidates'].isNotEmpty) {
          final content = responseBody['candidates'][0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            return content['parts'][0]['text'] ?? '';
          }

          LogService.instance.warn(
            'Google API 响应的 candidates 中没有 content 或 parts。响应体: ${response.body}',
          );
          return '';
        }

        final errorMsg = 'LLM 响应不包含 "candidates" 字段。响应体: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }

      final errorMsg = 'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
      LogService.instance.error(errorMsg);
      throw Exception(errorMsg);
    } catch (e, s) {
      LogService.instance.error('Google 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow;
    }
  }

  Future<String> _requestWithAnthropicFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    final uri = Uri.parse('${apiConfig.url}/messages');
    final headers = {
      'x-api-key': apiConfig.apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    };

    final bodyMap = <String, dynamic>{
      'model': apiConfig.model,
      'max_tokens': 60000,
      'temperature': 1,
      'messages': messages,
    };

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
          return responseBody['content'][0]['text'] ?? '';
        }

        final errorMsg = 'LLM 响应不包含 "content" 字段。响应体: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }

      final errorMsg = 'LLM 请求失败，状态码 ${response.statusCode}: ${response.body}';
      LogService.instance.error(errorMsg);
      throw Exception(errorMsg);
    } catch (e, s) {
      LogService.instance.error('Anthropic 格式请求出错，URL: ${apiConfig.url}', e, s);
      rethrow;
    }
  }
}
