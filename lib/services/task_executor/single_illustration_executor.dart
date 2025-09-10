// lib/services/task_executor/single_illustration_executor.dart

import 'dart:convert';
import 'package:tiktoken/tiktoken.dart';

import '../../models/book.dart';
import '../../base/config_service.dart';
import '../../services/llm_service/llm_service.dart';
import '../../services/drawing_service/drawing_service.dart';
import '../../models/character_card_model.dart';
import '../../base/default_configs.dart';
import '../prompt_builder/draw_prompt_builder.dart';
import '../prompt_builder/llm_prompt_builder.dart';

class SingleIllustrationExecutor {
  final LlmPromptBuilder _llmPromptBuilder;
  final DrawPromptBuilder _drawPromptBuilder;

  SingleIllustrationExecutor._()
      : _configService = ConfigService(),
        _llmPromptBuilder = LlmPromptBuilder(ConfigService()),
        _drawPromptBuilder = DrawPromptBuilder(ConfigService());

  static final SingleIllustrationExecutor instance = SingleIllustrationExecutor._();

  // 依赖的服务
  final ConfigService _configService;
  final LlmService _llmService = LlmService.instance;
  final DrawingService _drawingService = DrawingService.instance;

  /// "此处生成插图"功能
  Future<void> generateIllustrationHere({
    required Book book,
    required ChapterStructure chapter,
    required LineStructure line,
    required String imageSaveDir,
  }) async {
    // 1. 提取上下文
    final contextText = _extractContextAroundLine(line, chapter, 4000);

    // 2. 调用LLM生成绘图数据
    final illustrationsData = await _generateAndParseIllustrationData(contextText, 1);
    if (illustrationsData.isEmpty) {
      throw Exception("未能从LLM响应中解析出有效的绘图项。");
    }
    
    final itemData = illustrationsData.first;
    final llmPrompt = itemData['prompt'] as String?;
    final lineNumber = line.lineNumberInSourceFile; // 强制使用目标行的行号

    if (llmPrompt == null) {
        throw Exception("LLM未能生成有效的prompt。");
    }

    // 3. 构建最终绘画提示词
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: llmPrompt);

    // 4. 调用绘图服务生成并保存图片
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineNumber: lineNumber,
      saveDir: imageSaveDir,
      contextText: contextText, // 传递上下文用于角色匹配
      //  将最终的绘画提示词保存到 sceneDescription 中
      sceneDescriptionToSave: positivePrompt,
    );
  }

  /// "重新生成插图"功能
  Future<void> regenerateIllustration({
    required ChapterStructure chapter,
    required LineStructure line,
    required String imageSaveDir,
  }) async {
    // 从 sceneDescription 读取已存的提示词
    final String? positivePrompt = line.sceneDescription;
    if (positivePrompt == null || positivePrompt.isEmpty) {
      throw Exception("该行没有可用于重新生成的绘画提示词。请先'此处生成插图'。");
    }

    // 从配置中获取负面提示词
    final negativePrompt = _configService.getActiveTagContent('drawing_negative_tags', 'active_drawing_negative_tag_id');
    
    // 提取上下文用于角色参考图匹配
    final contextText = _extractContextAroundLine(line, chapter, 4000);

    // 直接调用绘图服务生成并保存图片
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineNumber: line.lineNumberInSourceFile,
      saveDir: imageSaveDir,
      contextText: contextText, // 传递上下文
      // 保留原有的 sceneDescription
      sceneDescriptionToSave: positivePrompt,
    );
  }

  // 统一的绘图和保存逻辑
  Future<void> _drawAndSaveImages({
    required String positivePrompt,
    required String negativePrompt,
    required ChapterStructure chapter,
    required int lineNumber,
    required String saveDir,
    required String sceneDescriptionToSave,
    required String contextText, // 新增：用于查找角色参考图
  }) async {
    final imagesPerScene = _configService.getSetting<int>('image_gen_images_per_scene', 2);
    final sizeString = _configService.getSetting<String>('image_gen_size', appDefaultConfigs['image_gen_size']);
    final sizeParts = sizeString.split('*').map((e) => int.tryParse(e) ?? 1024).toList();
    final width = sizeParts[0];
    final height = sizeParts[1];
    
    // 添加查找带参考图的角色的功能逻辑
    String? referenceImageForTask;
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    
    for (final card in allCards) {
      final characterNameToMatch = card.characterName.isNotEmpty ? card.characterName : card.name;
      // 移除行号信息，只匹配纯文本内容
      final plainTextContent = contextText.split('\n').map((e) => e.split(':').sublist(1).join(':').trim()).join('\n');
      if (characterNameToMatch.isNotEmpty && plainTextContent.contains(characterNameToMatch)) {
        final imagePath = card.referenceImagePath;
        final imageUrl = card.referenceImageUrl;
        if ((imagePath != null && imagePath.isNotEmpty) || (imageUrl != null && imageUrl.isNotEmpty)) {
          referenceImageForTask = imagePath ?? imageUrl;
          print("[角色匹配] ✅ 在文本中找到角色 '$characterNameToMatch'，将使用参考图进行生成: $referenceImageForTask");
          break; // 找到第一个就停止
        }
      }
    }

    final activeApi = _configService.getActiveDrawingApi();

    final imagePaths = await _drawingService.generateImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      saveDir: saveDir,
      count: imagesPerScene,
      width: width,
      height: height,
      apiConfig: activeApi,
      referenceImagePath: referenceImageForTask, // 传递参考图路径
    );

    if (imagePaths != null && imagePaths.isNotEmpty) {
      chapter.addIllustrationsToLine(lineNumber, imagePaths, sceneDescriptionToSave);
    } else {
      throw Exception("绘图服务未能生成图片。");
    }
  }

  String _extractContextAroundLine(LineStructure targetLine, ChapterStructure chapter, int maxTokens) {
    final encoding = encodingForModel("gpt-4");
    final lines = chapter.lines;
    final targetIndex = lines.indexOf(targetLine);
    if (targetIndex == -1) return targetLine.text;

    List<String> contextLines = ["${targetLine.lineNumberInSourceFile}: ${targetLine.text}"];
    int currentTokens = encoding.encode(targetLine.text).length;

    int before = targetIndex - 1;
    int after = targetIndex + 1;

    while (currentTokens < maxTokens && (before >= 0 || after < lines.length)) {
      if (before >= 0) {
        final line = lines[before];
        final lineContent = "${line.lineNumberInSourceFile}: ${line.text}";
        final lineTokens = encoding.encode(lineContent).length;
        if (currentTokens + lineTokens <= maxTokens) {
          contextLines.insert(0, lineContent);
          currentTokens += lineTokens;
        }
        before--;
      }
      if (currentTokens >= maxTokens) break;

      if (after < lines.length) {
        final line = lines[after];
        final lineContent = "${line.lineNumberInSourceFile}: ${line.text}";
        final lineTokens = encoding.encode(lineContent).length;
        if (currentTokens + lineTokens <= maxTokens) {
          contextLines.add(lineContent);
          currentTokens += lineTokens;
        }
        after++;
      }
    }
    return contextLines.join('\n');
  }

  Future<List<Map<String, dynamic>>> _generateAndParseIllustrationData(String textContent, int numScenes) async {
    // 使用新的Builder构建LLM请求的提示
    final (systemPrompt, messages) = _llmPromptBuilder.build(textContent: textContent, numScenes: numScenes);
    try {
      final activeApi = _configService.getActiveLanguageApi();
      
      // [需求 1] 移除速度限制器调用
      // final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);
      // await llmRateLimiter.acquire();
      
      final llmResponse = await _llmService.requestCompletion(systemPrompt: systemPrompt, messages: messages, apiConfig: activeApi);

      // 1. 从Markdown代码块中提取内容（如果存在）
      String potentialJson = llmResponse;
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```', dotAll: true).firstMatch(llmResponse);
      if (jsonMatch != null) {
        potentialJson = jsonMatch.group(1) ?? llmResponse;
      }
      potentialJson = potentialJson.trim();

      // 2. 主要尝试：解析JSON数组 `[...]`
      final startIndex = potentialJson.indexOf('[');
      final endIndex = potentialJson.lastIndexOf(']');

      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        final jsonString = potentialJson.substring(startIndex, endIndex + 1);
        final data = jsonDecode(jsonString);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }

      // 3. 回退尝试：如果LLM返回了单个对象 `{...}` 而不是数组
      final startBraceIndex = potentialJson.indexOf('{');
      final endBraceIndex = potentialJson.lastIndexOf('}');
      if (startBraceIndex != -1 && endBraceIndex != -1 && endBraceIndex > startBraceIndex) {
        final jsonString = potentialJson.substring(startBraceIndex, endBraceIndex + 1);
        final data = jsonDecode(jsonString);
        if (data is Map<String, dynamic>) {
          // 将单个对象包装在列表中以匹配返回类型
          return [data]; 
        }
      }

      // 如果两种尝试都失败
      print('未能从LLM响应中解析出有效的JSON数组或对象。');
      print('原始响应: $llmResponse');
      return [];

    } catch (e) {
      print('处理LLM响应时失败: $e');
      return [];
    }
  }
}