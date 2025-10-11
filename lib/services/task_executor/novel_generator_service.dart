// lib/services/task_executor/novel_generator_service.dart

import 'dart:convert';
import '../llm_service/llm_service.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';

class NovelGeneratorService {
  NovelGeneratorService._();
  static final NovelGeneratorService instance = NovelGeneratorService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  Future<Map<String, dynamic>> generateNovelOutline({
    required String storyPrompt,
    required int chapterCount,
    required int wordsPerChapter,
    String? backgroundSetting,
    String? writingStyle,
    List<Map<String, dynamic>>? mainCharacters,
  }) async {
    LogService.instance.info('NovelGeneratorService: 开始生成大纲...');
    final systemPrompt = """你是一个才华横溢的小说家和世界构建者。你的任务是根据用户的要求，创建一个详细、引人入胜的小说大纲。
如果用户提供了某些设定（如背景、文风或角色），请严格使用这些设定，不要重新生成。你只需要生成缺失的部分。

请严格按照以下JSON格式返回你的输出，不要添加任何额外的解释或文本：
{
  "title": "小说标题",
  "main_characters": [
    {
      "name": "卡片名称 (例如: 主角-艾拉)",
      "characterName": "角色名 (例如: 艾拉)",
      "identity": "角色身份",
      "appearance": "角色外貌",
      "clothing": "角色服装",
      "personality": "角色性格",
      "status": "初始状态",
      "other": "其他备注"
    }
  ],
  "background_setting": "详细的背景世界观设定",
  "writing_style": "建议的文风描述",
  "storyline": [
    {
      "chapter_title": "第一章的标题",
      "chapter_summary": "第一章的内容简述"
    }
  ]
}
""";

    final presetPrompts = StringBuffer();
    if (backgroundSetting != null && backgroundSetting.isNotEmpty) {
      presetPrompts.writeln("请使用以下背景设定：\n$backgroundSetting");
    }
    if (writingStyle != null && writingStyle.isNotEmpty) {
      presetPrompts.writeln("请使用以下文风：\n$writingStyle");
    }
    if (mainCharacters != null && mainCharacters.isNotEmpty) {
      presetPrompts.writeln("请使用以下主要角色设定：\n${jsonEncode(mainCharacters)}");
    }

    final userPrompt = """请为我创作一个小说大纲。
故事要求：$storyPrompt
章节数：$chapterCount
每章字数：约$wordsPerChapter字

$presetPrompts

请基于以上所有信息，生成一个完整的小说大纲。
如果背景、文风或角色已提供，请不要修改它们，只需生成尚未定义的其他部分（例如标题、故事线等）。
""";

    try {
      LogService.instance.info('NovelGeneratorService: 正在向 LLM 发送大纲生成请求...');
      final llmResponse = await _llmService.requestCompletion(
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
        apiConfig: _configService.getActiveLanguageApi(),
      );
      LogService.instance.info('NovelGeneratorService: 收到 LLM 的大纲响应。');

      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
      final jsonString = jsonMatch?.group(1) ?? llmResponse;
      
      try {
        return jsonDecode(jsonString);
      } catch (e, s) {
        LogService.instance.error('解析小说大纲 LLM 响应 JSON 失败。响应原文: $jsonString', e, s);
        rethrow;
      }
    } catch (e, s) {
      LogService.instance.error('调用 LLM Service 生成小说大纲时出错', e, s);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateChapterContent({
    required String title,
    required String backgroundSetting,
    required String writingStyle,
    required List<Map<String, dynamic>> mainCharacters,
    required List<Map<String, dynamic>> storyline,
    required int chapterIndex,
    required int wordsPerChapter,
  }) async {
     LogService.instance.info('NovelGeneratorService: 开始生成第 ${chapterIndex + 1} 章内容...');
     final systemPrompt = """你是一位经验丰富的小说家。你的任务是根据提供的大纲和设定，续写指定章节的详细内容。

请严格按照以下JSON格式返回你的输出，不要添加任何额外的解释或文本：
{
  "chapter_content": "这里是生成的完整章节内容...",
  "updated_characters": [
    {
      "name": "卡片名称",
      "characterName": "角色名",
      "identity": "角色身份",
      "appearance": "角色外貌",
      "clothing": "角色服装",
      "personality": "角色性格",
      "status": "在本章结束后，角色的最新状态",
      "other": "其他备注"
    }
  ],
  "new_chapter_summary": "根据你刚才生成的内容，为这一章生成一个新的、更详细的内容简述"
}
""";

    final currentChapter = storyline[chapterIndex];
    final charactersJson = jsonEncode(mainCharacters);
    final storylineJson = jsonEncode(storyline);

    final userPrompt = """请基于以下信息，为小说《$title》撰写第 ${chapterIndex + 1} 章的内容。

- **背景设定**: $backgroundSetting
- **文风设定**: $writingStyle
- **当前主要角色信息**: $charactersJson
- **完整故事线**: $storylineJson
- **本章目标**: 撰写标题为 “${currentChapter['chapter_title']}” 的章节，其核心内容是 “${currentChapter['chapter_summary']}”。
- **字数要求**: 约 $wordsPerChapter 字。

任务：
1. 生成该章节的完整内容。
2. 根据本章发生的故事，更新主要角色的'status'字段。
3. 为你生成的内容，提供一个新的、更详细的简述。
""";

    try {
      LogService.instance.info('NovelGeneratorService: 正在向 LLM 发送第 ${chapterIndex + 1} 章内容生成请求...');
      final llmResponse = await _llmService.requestCompletion(
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
        apiConfig: _configService.getActiveLanguageApi(),
      );
      LogService.instance.info('NovelGeneratorService: 收到 LLM 的第 ${chapterIndex + 1} 章内容响应。');

      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
      final jsonString = jsonMatch?.group(1) ?? llmResponse;
      
      try {
        return jsonDecode(jsonString);
      } catch (e, s) {
        LogService.instance.error('解析第 ${chapterIndex + 1} 章内容 LLM 响应 JSON 失败。响应原文: $jsonString', e, s);
        rethrow;
      }
    } catch (e, s) {
      LogService.instance.error('调用 LLM Service 生成第 ${chapterIndex + 1} 章内容时出错', e, s);
      rethrow;
    }
  }
}