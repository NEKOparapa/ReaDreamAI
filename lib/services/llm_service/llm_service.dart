// lib/services/llm_service/llm_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/api_model.dart';

/// 封装了对 LLM（大语言模型）的 API 请求。
/// 支持 OpenAI, Google, Anthropic 等多种 API 格式。
class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  final http.Client _client = http.Client();

  /// 向指定的 LLM 平台发送请求。
  Future<String> requestCompletion({
    String? systemPrompt,
    required List<Map<String, String>> messages,
    required ApiModel apiConfig,
  }) async {
    // 根据 api_format 分发到不同的请求处理器
    switch (apiConfig.format) {
      case ApiFormat.openai:
        return _requestWithOpenAiFormat(systemPrompt, messages, apiConfig);
      case ApiFormat.google:
        return _requestWithGoogleFormat(systemPrompt, messages, apiConfig);
      case ApiFormat.anthropic:
        return _requestWithAnthropicFormat(systemPrompt, messages, apiConfig);
    }
  }

  /// 使用 OpenAI 兼容的 API 格式发起请求。
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

    // 将 systemPrompt 和 messages 组合成 OpenAI 格式
    final allMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(messages);

    final body = jsonEncode({
      'model': apiConfig.model,
      'messages': allMessages,
      // 可在此处添加 temperature, top_p 等更多参数
    });

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty) {
          return responseBody['choices'][0]['message']['content'] ?? '';
        } else {
          throw Exception(
              'LLM response does not contain "choices". Body: ${response.body}');
        }
      } else {
        throw Exception(
            'LLM request failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error during OpenAI format request to ${apiConfig.url}: $e');
      rethrow;
    }
  }

  /// 使用 Google Gemini API 格式发起请求。
  Future<String> _requestWithGoogleFormat(
    String? systemPrompt,
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) async {
    // Google API 将 key 作为查询参数
    final uri = Uri.parse(
        '${apiConfig.url}/models/${apiConfig.model}:generateContent?key=${apiConfig.apiKey}');
    final headers = {
      'Content-Type': 'application/json',
    };

    // Gemini API 没有独立的 system prompt 字段，通常将其内容附加到第一条 user message 前
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
        // 如果没有 user message，则创建一个
        processedMessages.insert(
            0, {'role': 'user', 'content': systemPrompt});
      }
    }
    
    // 转换为 Google 的 'contents' 格式，并将 'assistant' role 映射为 'model'
    final contents = processedMessages.map((msg) {
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      return {
        'role': role,
        'parts': [{'text': msg['content']}]
      };
    }).toList();


    final body = jsonEncode({'contents': contents});

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['candidates'] != null &&
            responseBody['candidates'].isNotEmpty) {
          return responseBody['candidates'][0]['content']['parts'][0]['text'] ?? '';
        } else {
          throw Exception(
              'LLM response does not contain "candidates". Body: ${response.body}');
        }
      } else {
        throw Exception(
            'LLM request failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error during Google format request to ${apiConfig.url}: $e');
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
    final headers = {
      'x-api-key': apiConfig.apiKey,
      'anthropic-version': '2023-06-01', // 推荐的稳定版本
      'Content-Type': 'application/json',
    };

    final bodyMap = {
      'model': apiConfig.model,
      'messages': messages, // Anthropic 的 messages 格式与 OpenAI 兼容
      'max_tokens': 20000, // Anthropic API 要求此参数
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      bodyMap['system'] = systemPrompt; // Anthropic 直接支持 system 字段
    }

    final body = jsonEncode(bodyMap);

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseBody['content'] != null &&
            responseBody['content'].isNotEmpty) {
          return responseBody['content'][0]['text'] ?? '';
        } else {
          throw Exception(
              'LLM response does not contain "content". Body: ${response.body}');
        }
      } else {
        throw Exception(
            'LLM request failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error during Anthropic format request to ${apiConfig.url}: $e');
      rethrow;
    }
  }
}