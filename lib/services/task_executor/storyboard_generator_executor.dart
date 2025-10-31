// lib/services/task_executor/storyboard_generator_executor.dart

import 'dart:convert';
import 'package:pool/pool.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';
import '../../models/book.dart';
import '../../models/character_card_model.dart';
import '../../services/llm_service/llm_service.dart';
import '../../ui/bookshelf/novel_to_short_drama/novel_to_short_drama_workbench_page.dart'
    show ChapterScript, Shot; // 导入Shot模型

// 定义返回类型
typedef StoryboardGenerationResult = ({
  List<ChapterScript> script,
  List<CharacterCard> characters
});

typedef ShotPromptsResult = ({String imagePrompt, String videoPrompt});

class StoryboardGeneratorExecutor {
  StoryboardGeneratorExecutor._();
  static final StoryboardGeneratorExecutor instance =
      StoryboardGeneratorExecutor._();

  final ConfigService _configService = ConfigService();
  final LlmService _llmService = LlmService.instance;
  final LogService _logger = LogService.instance;

  // --- 任务1: 为整本小说生成分镜脚本 ---
  Future<StoryboardGenerationResult> generateStoryboard({
    required Book book,
    required String requirements,
    required List<CharacterCard> characters,
    int? scenesPerChapter, // [新增]
    int? shotsPerScene,   // [新增]
  }) async {
    _logger.info("开始为《${book.title}》生成分镜脚本...");
    final pool = Pool(3); // 限制并发数为3
    // 存储每个章节的生成结果，包含索引、脚本JSON和角色JSON
    final results = <(int, Map<String, dynamic>)>[];

    try {
      // 并发处理所有章节
      await Future.wait(
        book.chapters.asMap().entries.map((entry) {
          final chapterIndex = entry.key;
          final chapter = entry.value;

          return pool.withResource(() async {
            _logger.info("正在处理章节 ${chapter.title}...");
            final chapterText = chapter.lines.map((l) => l.text).join('\n');

            final (systemPrompt, messages) = _buildPromptForStoryboardGeneration(
              novelTitle: book.title,
              chapterTitle: chapter.title,
              chapterText: chapterText,
              requirements: requirements,
              characters: characters,
              scenesPerChapter: scenesPerChapter, // [修改] 传递参数
              shotsPerScene: shotsPerScene,       // [修改] 传递参数
            );

            final llmResponse = await _llmService.requestCompletion(
              systemPrompt: systemPrompt,
              messages: messages,
              apiConfig: _configService.getActiveLanguageApi(),
            );

            // 解析返回的包含 script 和 characters 的JSON对象
            try {
              String jsonString = llmResponse;
              // 提取被 ```json ... ``` 包裹的内容
              final match = RegExp(r'```json\s*([\s\S]+?)\s*```')
                  .firstMatch(llmResponse);
              if (match != null) jsonString = match.group(1)!;

              final Map<String, dynamic> responseJson = jsonDecode(jsonString);
              results.add((chapterIndex, responseJson));
              _logger.success("章节 ${chapter.title} 处理成功。");
            } catch (e, s) {
              _logger.error("解析章节 ${chapter.title} 的LLM响应失败", e, s);
              // 即使失败也添加一个空结果，以保证章节顺序不错乱
              results.add((chapterIndex, {'script': [], 'characters': []}));
            }
          });
        }),
      );

      // --- 汇总和处理所有章节的结果 ---

      // 按章节索引排序，确保顺序正确
      results.sort((a, b) => a.$1.compareTo(b.$1));

      final finalScript = <ChapterScript>[];
      final allGeneratedCharacters = <CharacterCard>[];

      for (int i = 0; i < book.chapters.length; i++) {
        final chapter = book.chapters[i];
        // 查找对应章节的结果
        final chapterResult =
            results.firstWhere((r) => r.$1 == i, orElse: () => (i, {})).$2;

        // 1. 处理分镜脚本
        final scenesJson = chapterResult['script'] as List<dynamic>? ?? [];
        final chapterScript = ChapterScript.fromJson({
          'originalChapterTitle': chapter.title,
          'scenes': scenesJson,
        });
        finalScript.add(chapterScript);

        // 2. 收集AI生成的角色
        if (characters.isEmpty) { // 仅当用户未提供角色时，才收集AI生成的角色
          final charactersJson = chapterResult['characters'] as List<dynamic>? ?? [];
          for (final charJson in charactersJson) {
            try {
              allGeneratedCharacters.add(CharacterCard.fromJson(charJson));
            } catch (e) {
              _logger.warn("解析AI生成的角色卡失败: $charJson, 错误: $e");
            }
          }
        }
      }
      
      // 对所有收集到的AI角色进行去重
      final uniqueCharacters = _deduplicateCharacters(allGeneratedCharacters);

      _logger.success("所有章节分镜脚本生成完毕！");
      return (script: finalScript, characters: uniqueCharacters);

    } catch (e, s) {
      _logger.error("生成分镜脚本时发生严重错误", e, s);
      rethrow;
    }
  }

  // --- 任务2: 为单个分镜生成提示词 ---

  Future<ShotPromptsResult> generatePromptsForShot({
    required Shot shot,
    required List<CharacterCard> characters,
  }) async {
    _logger.info("为分镜 ${shot.shotNumber} 生成提示词...");
    // 1. 构建提示词
    final (systemPrompt, messages) = _buildPromptForShot(
      shotContent: shot.contentController.text,
      characters: characters,
    );

    // 2. 请求LLM
    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: messages,
      apiConfig: _configService.getActiveLanguageApi(),
    );

    // 3. 解析结果
    try {
      String jsonString = llmResponse;
      final match =
          RegExp(r'```json\s*([\s\S]+?)\s*```').firstMatch(llmResponse);
      if (match != null) jsonString = match.group(1)!;

      // 将解码后的对象强制转换为 Map<String, dynamic>
      final data = jsonDecode(jsonString) as Map<String, dynamic>; 
      
      // 在取值时确保类型为 String
      return (
        imagePrompt: data['image_prompt'] as String? ?? '',
        videoPrompt: data['video_prompt'] as String? ?? ''
      );
    } catch (e, s) {
      _logger.error("解析分镜 ${shot.shotNumber} 的提示词响应失败", e, s);
      return (imagePrompt: '', videoPrompt: ''); // 返回空结果
    }
  }

  // --- 私有方法: 提示词构建逻辑 ---

  /// [内联方法] 为“小说转短剧”生成分镜脚本构建提示词
  (String, List<Map<String, String>>) _buildPromptForStoryboardGeneration({
    required String novelTitle,
    required String chapterTitle,
    required String chapterText,
    required String requirements,
    required List<CharacterCard> characters,
    int? scenesPerChapter,
    int? shotsPerScene,
  }) {
    String characterInfoBlock = '';
    // 如果用户提供了角色信息，则将其加入提示词
    if (characters.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 主要角色信息 (请基于此信息进行创作):');
      for (final char in characters) {
        buffer.writeln('- 角色名: ${char.characterName}');
        if (char.appearance.isNotEmpty)
          buffer.writeln('  - 外貌: ${char.appearance}');
        if (char.clothing.isNotEmpty)
          buffer.writeln('  - 服装: ${char.clothing}');
        if (char.personality.isNotEmpty)
          buffer.writeln('  - 性格: ${char.personality}');
      }
      characterInfoBlock = buffer.toString();
    }

    // [修改] 更新System Prompt，移除time和location，要求信息合并到title
    const String systemPrompt = """你是一个专业的影视编剧和角色设计师。你的任务是将提供的小说章节内容，根据用户要求，改编成详细的分镜脚本。
### 任务要求:
1.  **场景划分**: 将章节内容合理地划分为多个场景（Scene）。每个场景的标题 `title` 字段应清晰地概括场景内容，并**在标题中包含时间和地点**（例如：“场景1 日/外景 - 森林边缘”）。
2.  **分镜设计**: 在每个场景内，设计一系列分镜（Shot）。每个分镜都需要包含以下元素：
    -   **景别 (shotType)**: 如全景、中景、近景、特写等。
    -   **运镜 (cameraMove)**: 如固定、推、拉、摇、跟等。
    -   **登场角色 (characters)**: 此分镜中出现的角色名。
    -   **画面内容 (content)**: 详细描述画面中发生的事情、人物的动作和表情。
    -   **声音/对白 (sound)**: 包含角色的对白、旁白或重要的环境音效。
    -   **分镜时长 (duration)**: 预估的时长，如 "3s", "5s"。
3.  **忠于原作**: 改编应在尊重小说原意的基础上进行，保留关键情节和对话。
4.  **遵循要求**: 严格遵守用户提供的额外“分镜要求”和“结构要求”。
5.  **角色生成 (重要)**:
    -   **如果用户提供了“主要角色信息”**: 你必须严格参考这些信息来创作分镜，并且在返回的`characters`数组中**返回一个空数组 `[]`**。
    -   **如果用户没有提供“主要角色信息”**: 你需要根据本章节内容，分析并识别出登场的主要角色，为他们创建角色简介。然后将这些角色信息填充到返回的`characters`数组中。

### 输出格式:
请严格以JSON格式返回一个根对象，该对象包含 `script` 和 `characters` 两个键。**注意：`script` 数组中的场景对象不再包含 `time` 和 `location` 字段。**
```json
{
  "script": [
    {
      "title": "场景1 日/外景 - 森林边缘",
      "shots": [
        {
          "shotNumber": 1,
          "shotType": "全景",
          "cameraMove": "固定",
          "characters": "主角A",
          "content": "广阔的森林边缘，主角A从树林中走出，显得疲惫不堪。",
          "sound": "风声，鸟鸣声。",
          "duration": "4s"
        }
      ]
    }
  ],
  "characters": [
    {
      "name": "主角A",
      "characterName": "李明",
      "appearance": "约20岁，黑发，眼神坚毅，脸上有少许尘土。",
      "clothing": "穿着破旧的皮夹克和牛仔裤。",
      "personality": "沉着冷静，不善言辞但内心强大。"
    }
  ]
}
```
""";
    
    String finalRequirements = requirements;
    final structureConstraints = StringBuffer();
    if (scenesPerChapter != null) {
      structureConstraints.writeln('- 请为本章节生成大约 $scenesPerChapter 个场景。');
    }
    if (shotsPerScene != null) {
      structureConstraints.writeln('- 请为每个场景生成大约 $shotsPerScene 个分镜。');
    }

    if (structureConstraints.isNotEmpty) {
      finalRequirements = '$finalRequirements\n\n### 结构要求:\n${structureConstraints.toString()}';
    }

    final realUserPrompt = """
### 小说标题: 《$novelTitle》
### 章节标题: 《$chapterTitle》

### 分镜要求:
${finalRequirements.isNotEmpty ? finalRequirements : "无特殊要求，请按专业标准生成。"}

$characterInfoBlock

### 章节原文:
---
$chapterText
---

请根据以上信息，为本章节生成分镜脚本和角色信息。
""";

    final messages = [
      {'role': 'user', 'content': realUserPrompt},
    ];
    return (systemPrompt, messages);
  }

  /// [内联方法] 为分镜生成首帧图片和视频的提示词
  (String, List<Map<String, String>>) _buildPromptForShot({
    required String shotContent,
    required List<CharacterCard> characters,
  }) {
    String characterInfoBlock = '';
    if (characters.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 参考角色信息:');
      for (final char in characters) {
        buffer.writeln('- 角色名: ${char.characterName}');
        if (char.appearance.isNotEmpty)
          buffer.writeln('  - 外貌: ${char.appearance}');
        if (char.clothing.isNotEmpty)
          buffer.writeln('  - 服装: ${char.clothing}');
      }
      characterInfoBlock = buffer.toString();
    }

    const String systemPrompt = """你是一个AI绘画和视频生成的提示词专家。你的任务是根据提供的分镜脚本内容，生成一个用于生成“首帧图片”的英文提示词和一个用于生成“视频”的英文提示词。

### 任务要求:
1.  **首帧图片提示词 (image_prompt)**:
    -   应详细、具体，描述一个静态画面。
    -   包含主体、外貌、服装、姿态、情绪、构图、环境、光影等。
    -   使用AI绘画标签化的语言（如 `1boy, solo, looking at viewer, ...`）。
    -   **不包含**任何动态描述（如 running, walking, smiling）。
    -   **不包含**任何风格或画质词（如 `masterpiece, best quality, anime style`）。

2.  **视频提示词 (video_prompt)**:
    -   应简洁、有力，专注于描述**动态**。
    -   描述画面中发生的核心运动或变化。
    -   可以包含运镜描述（如 `camera slowly zooms in`）。
    -   是对首帧图片的动态化延展。

### 输出格式:
请严格以JSON格式返回。
```json
{
  "image_prompt": "1boy, solo, short black hair, determined eyes, wearing silver armor, red cape, standing on a desolate battlefield, hand on sword hilt, rain, mud, stormy sky, dramatic lighting, full body shot.",
  "video_prompt": "The knight slowly raises his shimmering sword, rain intensifies splashing on his armor, camera slowly pushes in on his determined face."
}
```
""";

    final realUserPrompt = """
$characterInfoBlock

### 分镜画面内容:
---
$shotContent
---

请为以上分镜内容生成“首帧图片提示词”和“视频提示词”。
""";

    final messages = [
      {'role': 'user', 'content': realUserPrompt},
    ];
    return (systemPrompt, messages);
  }

  /// 私有辅助方法：对角色列表进行去重
  List<CharacterCard> _deduplicateCharacters(List<CharacterCard> characters) {
    final uniqueCharacters = <String, CharacterCard>{};
    for (final char in characters) {
      // 使用 `characterName` 作为唯一键，如果不存在则添加
      uniqueCharacters.putIfAbsent(char.characterName, () => char);
    }
    return uniqueCharacters.values.toList();
  }
}