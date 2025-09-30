// lib/services/task_executor/character_extractor.dart

import 'dart:convert';
import '../../base/config_service.dart';
import '../../models/character_card_model.dart';
import '../llm_service/llm_service.dart';
import '../../base/log/log_service.dart';
import 'package:uuid/uuid.dart';

/// 角色卡片提取执行器
class CharacterExtractor {
  // 私有构造函数，用于实现单例模式
  CharacterExtractor._() : _configService = ConfigService();

  // 提供全局唯一的静态实例
  static final CharacterExtractor instance = CharacterExtractor._();

  // 依赖的服务
  final ConfigService _configService;
  final LlmService _llmService = LlmService.instance;
  final LogService _logger = LogService.instance;

  /// 从文本中提取角色卡片
  Future<List<CharacterCard>> extractCharacters({
    required String textContent,
    required String genderFilter, // 'male', 'female', 'all'
    required String outputLanguage, // 'en', 'zh'
  }) async {
    // 构建系统提示词
    final systemPrompt = _buildSystemPrompt(outputLanguage);
    
    // 构建用户提示词
    final userPrompt = _buildUserPrompt(textContent, genderFilter, outputLanguage);
    
    final messages = [
      {'role': 'user', 'content': userPrompt}
    ];
    
    try {
      // 调用 LLM 服务
      final activeApi = _configService.getActiveLanguageApi();
      final llmResponse = await _llmService.requestCompletion(
        systemPrompt: systemPrompt, 
        messages: messages, 
        apiConfig: activeApi
      );
      
      _logger.info('LLM响应: $llmResponse');
      
      // 解析响应
      final characters = _parseResponse(llmResponse);
      return characters;
      
    } catch (e, s) {
      _logger.error('角色提取失败', e, s);
      rethrow;
    }
  }

  String _buildSystemPrompt(String outputLanguage) {
    if (outputLanguage == 'zh') {
      return '''你是一个专业的角色分析助手。你的任务是从给定的文本中提取角色信息，并生成详细的角色卡片。

要求：
1. 仔细阅读文本，识别所有出现的角色
2. 为每个角色提取以下信息：
   - 角色名字（在文本中的称呼）
   - 身份（性别、年龄、职业、社会地位等）
   - 外貌特征（发型、发色、眼睛、身高、体型等）
   - 服装配饰（衣服、饰品、装备等）
   - 其他特征（性格、特殊能力、标志性动作等）
3. 所有描述使用中文
4. 使用具体、视觉化的语言描述
5. 每个字段的描述要简洁但准确''';
    } else {
      return '''You are a professional character analysis assistant. Your task is to extract character information from the given text and generate detailed character cards.

Requirements:
1. Carefully read the text and identify all appearing characters
2. Extract the following information for each character:
   - Character name (as mentioned in the text)
   - Identity (gender, age, occupation, social status, etc.)
   - Appearance (hairstyle, hair color, eyes, height, body type, etc.)
   - Clothing & Accessories (clothes, accessories, equipment, etc.)
   - Other features (personality, special abilities, signature moves, etc.)
3. All descriptions should be in English
4. Use specific, visual language for descriptions
5. Keep descriptions concise but accurate''';
    }
  }

  String _buildUserPrompt(String textContent, String genderFilter, String outputLanguage) {
    String genderInstruction = '';
    if (genderFilter == 'male') {
      genderInstruction = outputLanguage == 'zh' ? '只提取男性角色。' : 'Extract only male characters.';
    } else if (genderFilter == 'female') {
      genderInstruction = outputLanguage == 'zh' ? '只提取女性角色。' : 'Extract only female characters.';
    } else {
      genderInstruction = outputLanguage == 'zh' ? '提取所有角色。' : 'Extract all characters.';
    }

    final textLabel = outputLanguage == 'zh' ? '### 文本内容:' : '### Text Content:';
    final outputFormatLabel = outputLanguage == 'zh' ? '### JSON输出格式:' : '### JSON Output Format:';

    return '''$genderInstruction

$textLabel
---
$textContent
---

$outputFormatLabel
```json
[
  {
    "characterName": "角色在文本中的名字",
    "identity": "身份描述",
    "appearance": "外貌描述", 
    "clothing": "服装描述",
    "other": "其他特征"
  }
]
```''';
  }

  List<CharacterCard> _parseResponse(String response) {
    try {
      // 提取JSON内容
      String jsonContent = response;
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```', dotAll: true).firstMatch(response);
      if (jsonMatch != null) {
        jsonContent = jsonMatch.group(1) ?? response;
      }
      
      // 找到JSON数组的开始和结束
      final startIndex = jsonContent.indexOf('[');
      final endIndex = jsonContent.lastIndexOf(']');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        jsonContent = jsonContent.substring(startIndex, endIndex + 1);
      }
      
      // 解析JSON
      final List<dynamic> charactersJson = jsonDecode(jsonContent);
      final List<CharacterCard> characters = [];
      
      for (final json in charactersJson) {
        final card = CharacterCard(
          id: const Uuid().v4(),
          name: json['characterName'] ?? '未命名角色',
          characterName: json['characterName'] ?? '',
          identity: json['identity'] ?? '',
          appearance: json['appearance'] ?? '',
          clothing: json['clothing'] ?? '',
          other: json['other'] ?? '',
          isSystemPreset: false,
        );
        characters.add(card);
      }
      
      return characters;
      
    } catch (e, s) {
      _logger.error('解析角色提取响应失败。原始响应: $response', e, s);
      throw Exception('解析响应失败');
    }
  }
}
