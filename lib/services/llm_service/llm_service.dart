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

  /// 按接口格式分发思考参数；关闭开关时保持旧行为，不向请求体写入任何思考字段。
  static void applyThinkingConfig(
    Map<String, dynamic> bodyMap,
    ApiModel apiConfig,
  ) {
    if (!apiConfig.thinkingEnabled) {
      return;
    }

    switch (apiConfig.format) {
      case ApiFormat.openai:
        _applyOpenAiThinkingConfig(bodyMap, apiConfig);
        break;
      case ApiFormat.google:
        _applyGoogleThinkingConfig(bodyMap, apiConfig);
        break;
      case ApiFormat.anthropic:
        _applyAnthropicThinkingConfig(bodyMap, apiConfig);
        break;
      case ApiFormat.none:
        break;
    }
  }

  static void _applyOpenAiThinkingConfig(
    Map<String, dynamic> bodyMap,
    ApiModel apiConfig,
  ) {
    // OpenAI 兼容格式内部再按官方平台区分，其他平台走 reasoning_effort 兜底。
    switch (apiConfig.provider) {
      case ApiProvider.deepseek:
        // DeepSeek 支持 thinking 开关，但 reasoning_effort 只接受 high / max；
        // 官方兼容规则是 low / medium 映射到 high，xhigh 映射到 max。
        bodyMap['thinking'] = {'type': 'enabled'};
        switch (apiConfig.thinkingDepth) {
          case LlmThinkingDepth.low:
          case LlmThinkingDepth.medium:
          case LlmThinkingDepth.high:
            bodyMap['reasoning_effort'] = LlmThinkingDepth.high.name;
            break;
          case LlmThinkingDepth.xhigh:
            bodyMap['reasoning_effort'] = 'max';
            break;
        }
        return;
      case ApiProvider.volcengine:
        // 火山方舟支持 thinking.type，并用 minimal / low / medium / high 调节思考长度；
        // 我们的 UI 没有 minimal，xhigh 也不是火山档位，因此超高降级为 high。
        bodyMap['thinking'] = {'type': 'enabled'};
        bodyMap['reasoning_effort'] =
            apiConfig.thinkingDepth == LlmThinkingDepth.xhigh
            ? LlmThinkingDepth.high.name
            : apiConfig.thinkingDepth.name;
        return;
      case ApiProvider.openai:
        // OpenAI 原生支持 low / medium / high / xhigh。
        bodyMap['reasoning_effort'] = apiConfig.thinkingDepth.name;
        return;
      default:
        // 自定义 OpenAI 兼容接口优先使用最通用的 reasoning_effort。
        bodyMap['reasoning_effort'] = apiConfig.thinkingDepth.name;
        return;
    }
  }

  static void _applyGoogleThinkingConfig(
    Map<String, dynamic> bodyMap,
    ApiModel apiConfig,
  ) {
    // Google 的思考参数挂在 generationConfig.thinkingConfig 下。
    final rawGenerationConfig = bodyMap['generationConfig'];
    final Map<String, dynamic> generationConfig;
    if (rawGenerationConfig is Map<String, dynamic>) {
      generationConfig = rawGenerationConfig;
    } else if (rawGenerationConfig is Map) {
      generationConfig = Map<String, dynamic>.from(rawGenerationConfig);
      bodyMap['generationConfig'] = generationConfig;
    } else {
      generationConfig = <String, dynamic>{};
      bodyMap['generationConfig'] = generationConfig;
    }

    final rawThinkingConfig = generationConfig['thinkingConfig'];
    final Map<String, dynamic> thinkingConfig;
    if (rawThinkingConfig is Map<String, dynamic>) {
      thinkingConfig = rawThinkingConfig;
    } else if (rawThinkingConfig is Map) {
      thinkingConfig = Map<String, dynamic>.from(rawThinkingConfig);
      generationConfig['thinkingConfig'] = thinkingConfig;
    } else {
      thinkingConfig = <String, dynamic>{};
      generationConfig['thinkingConfig'] = thinkingConfig;
    }

    final model = apiConfig.model.toLowerCase();
    final depth = apiConfig.thinkingDepth;

    if (model.contains('gemini-3')) {
      // Gemini 3 使用 thinkingLevel；Pro 只保留 low/high，Flash 可保留 medium。
      if (model.contains('flash')) {
        thinkingConfig['thinkingLevel'] = depth == LlmThinkingDepth.xhigh
            ? LlmThinkingDepth.high.name
            : depth.name;
      } else {
        thinkingConfig['thinkingLevel'] = depth == LlmThinkingDepth.low
            ? LlmThinkingDepth.low.name
            : LlmThinkingDepth.high.name;
      }
      return;
    }

    // Gemini 2.5 使用 thinkingBudget，四档映射为递增 token 预算。
    switch (depth) {
      case LlmThinkingDepth.low:
        thinkingConfig['thinkingBudget'] = 1024;
        break;
      case LlmThinkingDepth.medium:
        thinkingConfig['thinkingBudget'] = 4096;
        break;
      case LlmThinkingDepth.high:
        thinkingConfig['thinkingBudget'] = 8192;
        break;
      case LlmThinkingDepth.xhigh:
        thinkingConfig['thinkingBudget'] = 24576;
        break;
    }
  }

  static void _applyAnthropicThinkingConfig(
    Map<String, dynamic> bodyMap,
    ApiModel apiConfig,
  ) {
    // Anthropic 不同 Claude 版本的思考参数差异较大，这里集中做模型名兼容判断。
    final model = apiConfig.model.toLowerCase().replaceAll('_', '-');
    final depth = apiConfig.thinkingDepth;

    final isMythos = model.contains('mythos');
    final usesAdaptiveThinking =
        model.contains('4-6') ||
        model.contains('4.6') ||
        model.contains('4-7') ||
        model.contains('4.7');
    final supportsXhigh = model.contains('4-7') || model.contains('4.7');
    final supportsMax =
        isMythos ||
        model.contains('4-6') ||
        model.contains('4.6') ||
        supportsXhigh;
    final supportsEffort =
        isMythos ||
        model.contains('claude-4') ||
        model.contains('4-5') ||
        model.contains('4.5') ||
        usesAdaptiveThinking;

    final String effort;
    if (depth != LlmThinkingDepth.xhigh) {
      effort = depth.name;
    } else if (supportsXhigh) {
      effort = LlmThinkingDepth.xhigh.name;
    } else if (supportsMax) {
      effort = 'max';
    } else {
      effort = LlmThinkingDepth.high.name;
    }

    // Mythos 只需要 output_config.effort，不额外发送 thinking 对象。
    if (isMythos) {
      final rawOutputConfig = bodyMap['output_config'];
      final Map<String, dynamic> outputConfig;
      if (rawOutputConfig is Map<String, dynamic>) {
        outputConfig = rawOutputConfig;
      } else if (rawOutputConfig is Map) {
        outputConfig = Map<String, dynamic>.from(rawOutputConfig);
        bodyMap['output_config'] = outputConfig;
      } else {
        outputConfig = <String, dynamic>{};
        bodyMap['output_config'] = outputConfig;
      }
      outputConfig['effort'] = effort;
      return;
    }

    // Claude 4.6+ 使用 adaptive thinking，并通过 effort 表示思考强度。
    if (usesAdaptiveThinking) {
      bodyMap['thinking'] = {'type': 'adaptive'};
      final rawOutputConfig = bodyMap['output_config'];
      final Map<String, dynamic> outputConfig;
      if (rawOutputConfig is Map<String, dynamic>) {
        outputConfig = rawOutputConfig;
      } else if (rawOutputConfig is Map) {
        outputConfig = Map<String, dynamic>.from(rawOutputConfig);
        bodyMap['output_config'] = outputConfig;
      } else {
        outputConfig = <String, dynamic>{};
        bodyMap['output_config'] = outputConfig;
      }
      outputConfig['effort'] = effort;
      return;
    }

    // 旧版 extended thinking 使用固定 token budget；保持小于当前 max_tokens。
    final int budgetTokens;
    switch (depth) {
      case LlmThinkingDepth.low:
        budgetTokens = 1024;
        break;
      case LlmThinkingDepth.medium:
        budgetTokens = 4096;
        break;
      case LlmThinkingDepth.high:
        budgetTokens = 8192;
        break;
      case LlmThinkingDepth.xhigh:
        budgetTokens = 32000;
        break;
    }

    bodyMap['thinking'] = {'type': 'enabled', 'budget_tokens': budgetTokens};

    // 支持 effort 的旧模型额外带上 output_config，提升兼容性。
    if (supportsEffort) {
      final rawOutputConfig = bodyMap['output_config'];
      final Map<String, dynamic> outputConfig;
      if (rawOutputConfig is Map<String, dynamic>) {
        outputConfig = rawOutputConfig;
      } else if (rawOutputConfig is Map) {
        outputConfig = Map<String, dynamic>.from(rawOutputConfig);
        bodyMap['output_config'] = outputConfig;
      } else {
        outputConfig = <String, dynamic>{};
        bodyMap['output_config'] = outputConfig;
      }
      outputConfig['effort'] = effort;
    }
  }

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

    final processedMessages = _prepareMessages(messages, apiConfig);
    final allMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(processedMessages);

    final bodyMap = <String, dynamic>{
      'model': apiConfig.model,
      'messages': allMessages,
      'temperature': 1,
    };
    applyThinkingConfig(bodyMap, apiConfig);
    final body = jsonEncode(bodyMap);

    LogService.instance.info('正在使用 OpenAI 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6000));

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

  List<Map<String, String>> _prepareMessages(
    List<Map<String, String>> messages,
    ApiModel apiConfig,
  ) {
    final processedMessages = List<Map<String, String>>.from(messages);
    if (_shouldRemoveLastAssistantMessage(processedMessages, apiConfig)) {
      processedMessages.removeLast();
    }
    return processedMessages;
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

    final processedMessages = _prepareMessages(messages, apiConfig);
    final contents = processedMessages.map((msg) {
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

    applyThinkingConfig(bodyMap, apiConfig);
    final body = jsonEncode(bodyMap);

    LogService.instance.info('正在使用 Google 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6000));

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
      'messages': _prepareMessages(messages, apiConfig),
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      bodyMap['system'] = systemPrompt;
    }

    applyThinkingConfig(bodyMap, apiConfig);
    final body = jsonEncode(bodyMap);

    LogService.instance.info('正在使用 Anthropic 格式向 ${apiConfig.url} 发起请求...');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6000));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        final content = responseBody['content'];
        if (content is List && content.isNotEmpty) {
          final textParts = <String>[];
          for (final part in content) {
            if (part is Map && part['type'] == 'text' && part['text'] != null) {
              textParts.add(part['text'].toString());
            }
          }

          if (textParts.isNotEmpty) {
            return textParts.join();
          }

          LogService.instance.warn(
            'Anthropic API 响应的 content 中没有 text block。响应体: ${response.body}',
          );
          return '';
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
