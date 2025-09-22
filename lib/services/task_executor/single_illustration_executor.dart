// lib/services/task_executor/single_illustration_executor.dart

import 'dart:convert';
import 'package:tiktoken/tiktoken.dart';

import '../../models/book.dart';
import '../../base/config_service.dart';
import '../../services/llm_service/llm_service.dart';
import '../../services/drawing_service/drawing_service.dart';
import '../../services/video_service/video_service.dart';
import '../../models/character_card_model.dart';
import '../../base/default_configs.dart';
import '../prompt_builder/draw_prompt_builder.dart';
import '../prompt_builder/llm_prompt_builder.dart';
import '../../base/log/log_service.dart'; // 导入日志服务

/// 单个插图生成任务的执行器
class SingleIllustrationExecutor {
  // 依赖的 Prompt 构建器
  final LlmPromptBuilder _llmPromptBuilder;
  final DrawPromptBuilder _drawPromptBuilder;

  // 私有构造函数，用于实现单例模式
  SingleIllustrationExecutor._()
      : _configService = ConfigService(),
        _llmPromptBuilder = LlmPromptBuilder(ConfigService()),
        _drawPromptBuilder = DrawPromptBuilder(ConfigService());

  // 提供全局唯一的静态实例
  static final SingleIllustrationExecutor instance = SingleIllustrationExecutor._();

  // 依赖的服务
  final ConfigService _configService;
  final LlmService _llmService = LlmService.instance;
  final DrawingService _drawingService = DrawingService.instance;
  final LogService _logger = LogService.instance; // 获取日志服务实例

  /// "重新生成插图"功能
  Future<void> regenerateIllustration({
    required ChapterStructure chapter,
    required LineStructure line,
    required String imageSaveDir,
  }) async {
    // 从 line.sceneDescription 读取已保存的绘画提示词
    final String? positivePrompt = line.sceneDescription;
    if (positivePrompt == null || positivePrompt.isEmpty) {
      throw Exception("该行没有可用于重新生成的绘画提示词。请先'此处生成插图'。");
    }

    // 从配置中获取负面提示词
    final negativePrompt = _configService.getActiveTagContent('drawing_negative_tags', 'active_drawing_negative_tag_id');
    
    // 提取上下文文本，用于后续的角色参考图匹配
    final contextText = _extractContextAroundLine(line, chapter, 4000);

    // 直接调用统一的绘图和保存方法
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineId: line.id,
      saveDir: imageSaveDir,
      contextText: contextText, // 传递上下文用于角色匹配
      // 保留原有的 sceneDescription 不变
      sceneDescriptionToSave: positivePrompt,
    );
  }


  /// "为划选文本生成插图"功能
  Future<void> generateIllustrationForSelection({
    required Book book,
    required ChapterStructure chapter,
    required LineStructure targetLine,
    required String selectedText,
    required String imageSaveDir,
  }) async {
    // 1. 提取上下文：以划选区域为中心，扩展约6000 token，为LLM提供更丰富的背景信息
    final contextText = _extractContextAroundLine(targetLine, chapter, 6000);

    // 2. 构建LLM提示词：调用 prompt 构建器，传入完整上下文和用户划选的文本
    final (systemPrompt, messages) = _llmPromptBuilder.buildForSelectedScene(
      contextText: contextText,
      selectedText: selectedText,
    );
    
    // 3. 调用 LLM 服务获取场景描述，并解析返回的JSON
    final activeApi = _configService.getActiveLanguageApi();
    final llmResponse = await _llmService.requestCompletion(systemPrompt: systemPrompt, messages: messages, apiConfig: activeApi);

    Map<String, dynamic> itemData;
    try {
      // 尝试从可能包含 markdown 代码块的响应中提取纯净的 JSON 字符串
      String potentialJson = llmResponse;
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```', dotAll: true).firstMatch(llmResponse);
      if (jsonMatch != null) {
        potentialJson = jsonMatch.group(1) ?? llmResponse;
      }
      // 找到第一个 '{' 和最后一个 '}' 来截取 JSON 对象，提高解析成功率
      final startBraceIndex = potentialJson.indexOf('{');
      final endBraceIndex = potentialJson.lastIndexOf('}');
      if (startBraceIndex != -1 && endBraceIndex != -1 && endBraceIndex > startBraceIndex) {
        final jsonString = potentialJson.substring(startBraceIndex, endBraceIndex + 1);
        itemData = jsonDecode(jsonString);
      } else {
        throw Exception("未能从LLM响应中解析出有效的JSON对象。");
      }
    } catch (e, s) {
      // 如果解析失败，记录错误日志并抛出异常
      _logger.error('处理LLM响应失败。原始响应: $llmResponse', e, s);
      throw Exception("解析LLM响应失败。");
    }

    final llmPrompt = itemData['prompt'] as String?;
    if (llmPrompt == null) {
      throw Exception("LLM未能生成有效的prompt。");
    }

    // 4. 构建最终的绘画正/负面提示词
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: llmPrompt);

    // 5. 调用统一的绘图和保存方法
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineId: targetLine.id, // 插图将附加到用户划选文本的最后一行
      saveDir: imageSaveDir,
      contextText: contextText, // 传递上下文用于角色匹配
      sceneDescriptionToSave: positivePrompt, // 将生成的绘画提示词保存下来，用于后续的重新生成或视频生成
    );
  }


  /// 统一的绘图和保存逻辑封装
  Future<void> _drawAndSaveImages({
    required String positivePrompt,
    required String negativePrompt,
    required ChapterStructure chapter,
    required int lineId,
    required String saveDir,
    required String sceneDescriptionToSave,
    required String contextText, 
  }) async {
    // 从配置中读取生成参数
    final imagesPerScene = _configService.getSetting<int>('image_gen_images_per_scene', 2);
    final sizeString = _configService.getSetting<String>('image_gen_size', appDefaultConfigs['image_gen_size']);
    final sizeParts = sizeString.split('*').map((e) => int.tryParse(e) ?? 1024).toList();
    final width = sizeParts[0];
    final height = sizeParts[1];
    
    // 自动匹配角色参考图
    String? referenceImageForTask;
    final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
    final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
    
    for (final card in allCards) {
      // 优先使用 characterName 进行匹配，如果没有则使用卡片名 name
      final characterNameToMatch = card.characterName.isNotEmpty ? card.characterName : card.name;
      // 移除上下文中的行号信息，只在纯文本内容中进行匹配，提高准确性
      final plainTextContent = contextText.split('\n').map((e) => e.split(':').sublist(1).join(':').trim()).join('\n');
      
      // 如果上下文中包含角色名，并且该角色卡片有关联的参考图
      if (characterNameToMatch.isNotEmpty && plainTextContent.contains(characterNameToMatch)) {
        final imagePath = card.referenceImagePath;
        final imageUrl = card.referenceImageUrl;
        if ((imagePath != null && imagePath.isNotEmpty) || (imageUrl != null && imageUrl.isNotEmpty)) {
          referenceImageForTask = imagePath ?? imageUrl;
          _logger.success("[角色匹配] 在文本中找到角色 '$characterNameToMatch'，将使用参考图: $referenceImageForTask");
          break; // 找到第一个匹配的角色后就停止搜索
        }
      }
    }

    // 获取当前激活的绘画API配置
    final activeApi = _configService.getActiveDrawingApi();

    // 调用绘图服务生成图片
    final imagePaths = await _drawingService.generateImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      saveDir: saveDir,
      count: imagesPerScene,
      width: width,
      height: height,
      apiConfig: activeApi,
      referenceImagePath: referenceImageForTask, // 传递找到的参考图路径（可能为null）
    );

    // 如果成功生成图片，将其路径添加到数据模型中
    if (imagePaths != null && imagePaths.isNotEmpty) {
      chapter.addIllustrationsToLine(lineId, imagePaths, sceneDescriptionToSave);
    } else {
      throw Exception("绘图服务未能生成图片。");
    }
  }

  /// 以目标行为中心，提取指定token数量的上下文
  String _extractContextAroundLine(LineStructure targetLine, ChapterStructure chapter, int maxTokens) {
    // 使用 gpt-4 的分词器来计算 token 数量
    final encoding = encodingForModel("gpt-4");
    final lines = chapter.lines;
    final targetIndex = lines.indexOf(targetLine);
    if (targetIndex == -1) return targetLine.text;

    // 从目标行开始
    List<String> contextLines = ["${targetLine.id}: ${targetLine.text}"];
    int currentTokens = encoding.encode(targetLine.text).length;

    // 设置向前和向后的索引指针
    int before = targetIndex - 1;
    int after = targetIndex + 1;

    // 双向扩展，直到达到 token 上限或遍历完所有行
    while (currentTokens < maxTokens && (before >= 0 || after < lines.length)) {
      // 向前扩展
      if (before >= 0) {
        final line = lines[before];
        final lineContent = "${line.id}: ${line.text}";
        final lineTokens = encoding.encode(lineContent).length;
        if (currentTokens + lineTokens <= maxTokens) {
          contextLines.insert(0, lineContent); // 插入到列表开头
          currentTokens += lineTokens;
        }
        before--;
      }
      if (currentTokens >= maxTokens) break;

      // 向后扩展
      if (after < lines.length) {
        final line = lines[after];
        final lineContent = "${line.id}: ${line.text}";
        final lineTokens = encoding.encode(lineContent).length;
        if (currentTokens + lineTokens <= maxTokens) {
          contextLines.add(lineContent); // 添加到列表末尾
          currentTokens += lineTokens;
        }
        after++;
      }
    }
    // 将所有行拼接成一个字符串并返回
    return contextLines.join('\n');
  }

}

// ==================================================================
// 图生视频生成执行器
// ==================================================================
class SingleVideoExecutor {
  final LlmPromptBuilder _llmPromptBuilder;

  // 私有构造函数，用于实现单例模式
  SingleVideoExecutor._()
      : _configService = ConfigService(),
        _llmPromptBuilder = LlmPromptBuilder(ConfigService());

  // 提供全局唯一的静态实例
  static final SingleVideoExecutor instance = SingleVideoExecutor._();

  // 依赖的服务
  final ConfigService _configService;
  final LlmService _llmService = LlmService.instance;
  final VideoService _videoService = VideoService.instance;
  final LogService _logger = LogService.instance; // 获取日志服务实例

  /// "从插图生成视频"功能
  Future<void> generateVideoFromImage({
    required ChapterStructure chapter,
    required LineStructure line,
    required String imagePath, // 作为视频生成的参考图
    required String saveDir,
  }) async {
    _logger.info('[视频生成] 开始任务...');
    // 1. 检查是否存在用于生成视频的场景描述（即绘画提示词）
    final String? sceneDescription = line.sceneDescription;
    if (sceneDescription == null || sceneDescription.isEmpty) {
      throw Exception("该插图没有场景描述，无法生成视频。");
    }

    // 2. 调用 LLM 将绘画提示词转换为更适合视频生成的动态化提示词
    _logger.info('[视频生成] 调用LLM生成视频专用提示词');
    final (systemPrompt, messages) = _llmPromptBuilder.buildForVideoPrompt(
      sceneDescription: sceneDescription,
    );

    final activeApi = _configService.getActiveLanguageApi();
    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: messages,
      apiConfig: activeApi,
    );
    _logger.info('[视频生成] LLM响应: $llmResponse');
    
    // 3. 解析 LLM 响应，提取视频提示词
    String videoPrompt;
    try {
      // 同样使用健壮的JSON解析逻辑
      String potentialJson = llmResponse;
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```', dotAll: true).firstMatch(llmResponse);
      if (jsonMatch != null) {
        potentialJson = jsonMatch.group(1) ?? llmResponse;
      }
      final startBraceIndex = potentialJson.indexOf('{');
      final endBraceIndex = potentialJson.lastIndexOf('}');
      if (startBraceIndex != -1 && endBraceIndex != -1 && endBraceIndex > startBraceIndex) {
        final jsonString = potentialJson.substring(startBraceIndex, endBraceIndex + 1);
        final itemData = jsonDecode(jsonString);
        videoPrompt = itemData['prompt'] as String? ?? '';
      } else {
        throw Exception("未能从LLM响应中解析出有效的JSON对象。");
      }
    } catch (e, s) {
      _logger.error('处理LLM响应失败。原始响应: $llmResponse', e, s);
      throw Exception("解析LLM响应失败。");
    }

    if (videoPrompt.isEmpty) {
      throw Exception("LLM 未能生成有效的视频提示词。");
    }

    // 4. 从配置中获取视频生成参数
    final resolution = _configService.getSetting<String>('video_gen_resolution', '720p');
    final duration = _configService.getSetting<int>('video_gen_duration', 5);
    final activeVideoApi = _configService.getActiveVideoApi();

    // 5. 调用视频服务生成视频
    _logger.info('[视频生成] 调用视频服务，分辨率: $resolution, 时长: $duration 秒');
    final videoPaths = await _videoService.generateVideo(
      positivePrompt: videoPrompt,
      saveDir: saveDir,
      count: 1, // 每次通常只生成一个视频
      resolution: resolution,
      duration: duration,
      referenceImagePath: imagePath, // 关键：传入原插图作为参考
      apiConfig: activeVideoApi,
    );
    
    // 6. 将生成的视频路径保存到 book model
    if (videoPaths != null && videoPaths.isNotEmpty) {
      _logger.success('[视频生成] 生成成功，路径: $videoPaths');
      chapter.addVideosToLine(line.id, videoPaths);
    } else {
      throw Exception("视频服务未能生成视频。");
    }
  }
}