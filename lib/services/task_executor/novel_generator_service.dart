// lib/services/task_executor/novel_generator_service.dart

import 'dart:convert';
import '../llm_service/llm_service.dart';
import '../../base/config_service.dart';

/// AI小说生成服务
class NovelGeneratorService {
  NovelGeneratorService._();
  static final NovelGeneratorService instance = NovelGeneratorService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();

  /// 生成小说大纲
  Future<Map<String, dynamic>> generateNovelOutline({
    required String storyPrompt,
    required int chapterCount,
    required int wordsPerChapter,
  }) async {
    final systemPrompt = """你是一个才华横溢的小说家和世界构建者。你的任务是根据用户的要求，创建一个详细、引人入胜的小说大纲。

请严格按照以下JSON格式返回你的输出，不要添加任何额外的解释或文本：
{
  "title": "小说标题",
  "main_characters": [
    {
      "name": "角色名字",
      "identity": "角色身份",
      "appearance": "角色外貌",
      "personality": "角色性格",
      "costume": "角色服装",
      "status": "初始状态",
      "notes": "其他备注"
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

    final userPrompt = """请为我创作一个小说大纲。
故事要求：$storyPrompt
章节数：$chapterCount
每章字数：约$wordsPerChapter字

请生成故事的标题，主要角色（至少一个），背景设定，文风设定，以及从第一章到最后一章的故事线（每章都要有标题和内容简述）。
""";

    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
      apiConfig: _configService.getActiveLanguageApi(),
    );

    final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
    final jsonString = jsonMatch?.group(1) ?? llmResponse;
    
    return jsonDecode(jsonString);
  }

  /// 生成单章的完整内容
  Future<Map<String, dynamic>> generateChapterContent({
    required String title,
    required String backgroundSetting,
    required String writingStyle,
    required List<Map<String, dynamic>> mainCharacters,
    required List<Map<String, dynamic>> storyline,
    required int chapterIndex, // The 0-based index of the chapter to generate
    required int wordsPerChapter,
  }) async {
     final systemPrompt = """你是一位经验丰富的小说家。你的任务是根据提供的大纲和设定，续写指定章节的详细内容。

请严格按照以下JSON格式返回你的输出，不要添加任何额外的解释或文本：
{
  "chapter_content": "这里是生成的完整章节内容...",
  "updated_characters": [
    {
      "name": "角色名字",
      "identity": "角色身份",
      "appearance": "角色外貌",
      "personality": "角色性格",
      "costume": "角色服装",
      "status": "在本章结束后，角色的最新状态",
      "notes": "其他备注"
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

    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
      apiConfig: _configService.getActiveLanguageApi(),
    );

    final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
    final jsonString = jsonMatch?.group(1) ?? llmResponse;
    
    return jsonDecode(jsonString);
  }
}