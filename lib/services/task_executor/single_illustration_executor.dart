// lib/services/task_executor/single_illustration_executor.dart

import 'dart:convert';
import 'package:tiktoken/tiktoken.dart';

import '../../models/book.dart';
import '../../base/config_service.dart';
import '../../services/llm_service/llm_service.dart';
import '../../services/drawing_service/drawing_service.dart';
import '../../services/video_service/video_service.dart';
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
    // 解析 sceneDescription，兼容新旧格式
    final (prompt, characters) = _parseSceneDescription(line.sceneDescription);

    if (prompt.isEmpty) {
      throw Exception("该行没有可用于重新生成的绘画提示词。请先'此处生成插图'。");
    }

    // 从配置中获取负面提示词，并与原始绘画提示词组合
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: prompt);
    
    // 根据解析出的角色名查找参考图
    final referenceImagePath = _drawPromptBuilder.findReferenceImageForCharacters(characters);
     if (referenceImagePath != null) {
      _logger.info("[角色匹配] ✅ 重新生成将使用角色 ${characters.join(',')} 的参考图: $referenceImagePath");
    }

    // 直接调用统一的绘图和保存方法
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineId: line.id,
      saveDir: imageSaveDir,
      promptToSave: prompt, // 保存原始的LLM prompt
      charactersToSave: characters, // 保存登场角色列表
      referenceImagePath: referenceImagePath,
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
    // 提取登场角色
    final appearingCharacters = (itemData['appearing_characters'] as List<dynamic>? ?? []).cast<String>();

    // 4. 构建最终的绘画正/负面提示词
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: llmPrompt);
    
    // 根据登场角色查找参考图
    final referenceImagePath = _drawPromptBuilder.findReferenceImageForCharacters(appearingCharacters);
    if (referenceImagePath != null) {
      _logger.info("[角色匹配] ✅ 场景将使用角色 ${appearingCharacters.join(',')} 的参考图: $referenceImagePath");
    }

    // 5. 调用统一的绘图和保存方法
    await _drawAndSaveImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      chapter: chapter,
      lineId: targetLine.id, // 插图将附加到用户划选文本的最后一行
      saveDir: imageSaveDir,
      promptToSave: llmPrompt, // 保存从LLM获取的原始prompt
      charactersToSave: appearingCharacters, // 保存登场角色列表
      referenceImagePath: referenceImagePath,
    );
  }


  /// 统一的绘图和保存逻辑封装
  Future<void> _drawAndSaveImages({
    required String positivePrompt,
    required String negativePrompt,
    required ChapterStructure chapter,
    required int lineId,
    required String saveDir,
    required String promptToSave,
    required List<String> charactersToSave,
    String? referenceImagePath,
  }) async {
    // 从配置中读取生成参数
    final imagesPerScene = _configService.getSetting<int>('image_gen_images_per_scene', 2);
    final sizeString = _configService.getSetting<String>('image_gen_size', appDefaultConfigs['image_gen_size']);
    final sizeParts = sizeString.split('*').map((e) => int.tryParse(e) ?? 1024).toList();
    final width = sizeParts[0];
    final height = sizeParts[1];

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
      referenceImagePath: referenceImagePath, // 传递找到的参考图路径（可能为null）
    );

    // 如果成功生成图片，将其路径添加到数据模型中
    if (imagePaths != null && imagePaths.isNotEmpty) {
      // 保存prompt和角色列表
      chapter.addIllustrationsToLine(lineId, imagePaths, promptToSave, charactersToSave);
    } else {
      throw Exception("绘图服务未能生成图片。");
    }
  }

  /// 解析sceneDescription，兼容旧的纯文本格式和新的JSON格式
  (String, List<String>) _parseSceneDescription(String? description) {
    if (description == null || description.isEmpty) {
      return ('', []);
    }
    try {
      final data = jsonDecode(description);
      if (data is Map<String, dynamic>) {
        final prompt = data['prompt'] as String? ?? '';
        final characters = (data['characters'] as List<dynamic>? ?? []).cast<String>().toList();
        return (prompt, characters);
      }
      // 如果不是Map，但能被解析，当作旧数据处理
      return (description, []);
    } catch (e) {
      // 无法解析JSON，说明是旧格式的纯文本prompt
      return (description, []);
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
  final LogService _logger = LogService.instance;

  /// "从插图生成视频"功能
  Future<void> generateVideoFromImage({
    required ChapterStructure chapter,
    required LineStructure line,
    required String imagePath,
    required String saveDir,
  }) async {
    _logger.info('[视频生成] 开始任务...');
    // 1. 兼容解析 sceneDescription，获取静态场景描述
    final (sceneDescription, _) = _parseSceneDescription(line.sceneDescription);
    if (sceneDescription.isEmpty) {
      throw Exception("该插图没有场景描述，无法生成视频。");
    }

    // 2. 提取插图所在位置的上下文
    _logger.info('[视频生成] 正在提取约4000 tokens的上下文...');
    final contextText = _extractContextAroundLine(line, chapter, 4000);

    // 3. 调用 LLM 将绘画提示词和上下文转换为更适合视频生成的动态化提示词
    _logger.info('[视频生成] 调用LLM生成视频专用提示词');
    final (systemPrompt, messages) = _llmPromptBuilder.buildForVideoPrompt(
      sceneDescription: sceneDescription,
      contextText: contextText, // 传递上下文
    );

    final activeApi = _configService.getActiveLanguageApi();
    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: messages,
      apiConfig: activeApi,
    );
    _logger.info('[视频生成] LLM响应: $llmResponse');
    
    // 4. 解析 LLM 响应，提取视频提示词
    String videoPrompt;
    try {
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

    // 5. 从配置中获取视频生成参数
    final resolution = _configService.getSetting<String>('video_gen_resolution', '720p');
    final duration = _configService.getSetting<int>('video_gen_duration', 5);
    final activeVideoApi = _configService.getActiveVideoApi();

    // 6. 调用视频服务生成视频
    _logger.info('[视频生成] 正在调用视频服务......');
    final videoPaths = await _videoService.generateVideo(
      positivePrompt: videoPrompt,
      saveDir: saveDir,
      count: 1,
      resolution: resolution,
      duration: duration,
      referenceImagePath: imagePath,
      apiConfig: activeVideoApi,
    );
    
    // 7. 将生成的视频路径保存到 book model
    if (videoPaths != null && videoPaths.isNotEmpty) {
      _logger.success('[视频生成] 生成成功，路径: $videoPaths');
      chapter.addVideosToLine(line.id, videoPaths);
    } else {
      throw Exception("视频服务未能生成视频。");
    }
  }

  /// 以目标行为中心，提取指定token数量的上下文 (从SingleIllustrationExecutor复制而来)
  String _extractContextAroundLine(LineStructure targetLine, ChapterStructure chapter, int maxTokens) {
    final encoding = encodingForModel("gpt-4");
    final lines = chapter.lines;
    final targetIndex = lines.indexOf(targetLine);
    if (targetIndex == -1) return targetLine.text;

    List<String> contextLines = [targetLine.text]; // 初始只包含目标行文本
    int currentTokens = encoding.encode(targetLine.text).length;

    int before = targetIndex - 1;
    int after = targetIndex + 1;

    while (currentTokens < maxTokens && (before >= 0 || after < lines.length)) {
      if (before >= 0) {
        final line = lines[before];
        final lineContent = line.text;
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
        final lineContent = line.text;
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


  /// 解析sceneDescription，兼容新旧格式 (与 SingleIllustrationExecutor 中的方法重复，但为了模块独立性而保留)
  (String, List<String>) _parseSceneDescription(String? description) {
    if (description == null || description.isEmpty) {
      return ('', []);
    }
    try {
      final data = jsonDecode(description);
      if (data is Map<String, dynamic>) {
        final prompt = data['prompt'] as String? ?? '';
        final characters = (data['characters'] as List<dynamic>? ?? []).cast<String>().toList();
        return (prompt, characters);
      }
      return (description, []);
    } catch (e) {
      return (description, []);
    }
  }
}
// ==================================================================
// 文本改写/删除执行器
// ==================================================================
class TextModificationExecutor {
  TextModificationExecutor._();
  static final TextModificationExecutor instance = TextModificationExecutor._();

  final LlmPromptBuilder _llmPromptBuilder = LlmPromptBuilder(ConfigService());
  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();
  final LogService _logger = LogService.instance;

  // 改进后的 <textarea> 文本提取方法
  String _extractTextareaContent(String llmResponse) {
    // 优先匹配 <textarea> 标签
    final match = RegExp(r'<textarea>([\s\S]*?)</textarea>', multiLine: true).firstMatch(llmResponse);

    if (match != null && match.group(1) != null) {
      // 成功匹配，返回标签内的内容
      return match.group(1)!.trim();
    }
    
    // 匹配失败，执行备用逻辑
    _logger.warn('LLM 未按预期的 <textarea> 格式返回，启用备用检查逻辑。');
    
    final trimmedResponse = llmResponse.trim();
    final isLongEnough = trimmedResponse.length > 500;
    final containsTag = trimmedResponse.contains(RegExp(r'</?textarea>'));

    // 必须同时满足长度超过500且包含标签残留
    if (isLongEnough && containsTag) {
      _logger.warn('响应内容超过500字符且包含<textarea>标签残留，将视为有效内容并进行清理。');
      // 剔除任何可能存在的 <textarea> 或 </textarea> 标签并返回
      return llmResponse.replaceAll(RegExp(r'</?textarea>', multiLine: true), '').trim();
    } else {
      // 任何一个条件不满足，都视为错误响应
      _logger.error(
        'LLM响应不符合格式。检查失败: [内容长度 > 500: $isLongEnough, 包含标签残留: $containsTag]。响应原文: $llmResponse',
      );
      throw Exception('LLM响应不符合预期格式或内容过短。');
    }
  }

  Future<String> rewriteText({
    required String precedingText,
    required String selectedText,
    required String succeedingText,
    required String userRequirement,
  }) async {
    final (systemPrompt, messages) = _llmPromptBuilder.buildForTextRewrite(
      precedingText: precedingText,
      selectedText: selectedText,
      succeedingText: succeedingText,
      userRequirement: userRequirement,
    );
    final activeApi = _configService.getActiveLanguageApi();
    final llmResponse = await _llmService.requestCompletion(
        systemPrompt: systemPrompt, messages: messages, apiConfig: activeApi);
    return llmResponse.trim();
  }

  /// 重写整个章节
  Future<({String newTitle, String newContent})> rewriteChapter({
    required String originalContent,
    required String userRequirement,
  }) async {
    final activeApi = _configService.getActiveLanguageApi();

    // 1. 计算段落数
    final int paragraphCount = (originalContent.length / 1500).ceil();
    _logger.info('[章节重写] 原始字数: ${originalContent.length}, 计划生成 $paragraphCount 个段落。');

    // 2. 获取写作规划 (带重试机制)
    _logger.info('[章节重写] 正在向AI请求写作规划...');
    String newTitle = '';
    List<String> writingPlan = [];
    const maxPlanRetries = 2; // 总共尝试2次 (1次初始 + 1次重试)

    for (int i = 0; i < maxPlanRetries; i++) {
      try {
        final (planSys, planMsg) = _llmPromptBuilder.buildForChapterRewritePlan(
          originalContent: originalContent,
          userRequirement: userRequirement,
          paragraphCount: paragraphCount,
        );
        final planResponse = await _llmService.requestCompletion(
            systemPrompt: planSys, messages: planMsg, apiConfig: activeApi);

        String jsonString = planResponse;
        final match = RegExp(r'```json\s*([\s\S]+?)\s*```').firstMatch(planResponse);
        if (match != null) {
          jsonString = match.group(1)!;
        }
        final decoded = jsonDecode(jsonString);
        newTitle = decoded['new_title'] as String;
        writingPlan = (decoded['writing_plan'] as List).cast<String>();

        if (writingPlan.length != paragraphCount) {
          _logger.info('[章节重写] AI返回的规划段落数 (${writingPlan.length}) 与请求数 ($paragraphCount) 不符，将按返回的规划执行。');
        }
        _logger.info('[章节重写] 获取规划成功。新标题: "$newTitle", 大纲共 ${writingPlan.length} 条。');
        break; // 成功，跳出重试循环
      } catch (e, s) {
        _logger.error('[章节重写] 解析写作规划失败 (尝试 ${i + 1}/$maxPlanRetries)。原始响应：$e', e, s);
        if (i == maxPlanRetries - 1) { // 如果是最后一次尝试
          throw Exception('解析写作规划失败，请检查AI响应。');
        }
      }
    }
    
    // 如果规划为空，则无法继续
    if (writingPlan.isEmpty) {
      throw Exception('写作规划为空，无法继续重写章节。');
    }

    // 3. 线性续写 (带重试机制)
    final rewrittenContent = StringBuffer();
    const maxContentRetries = 3; // 总共尝试3次 (1次初始 + 2次重试)

    for (int i = 0; i < writingPlan.length; i++) {
      _logger.info('[章节重写] 正在续写第 ${i + 1}/${writingPlan.length} 段...');
      
      bool success = false;
      for (int j = 0; j < maxContentRetries; j++) {
        try {
          final (contSys, contMsg) = _llmPromptBuilder.buildForChapterContinuation(
            previouslyWrittenText: rewrittenContent.toString(),
            fullWritingPlan: writingPlan, // 传入完整大纲
            currentPlanIndex: i,         // 传入当前索引
          );
          final paragraphResponse = await _llmService.requestCompletion(
              systemPrompt: contSys, messages: contMsg, apiConfig: activeApi);

          // 使用新的提取方法
          final String content = _extractTextareaContent(paragraphResponse);

          if (content.isEmpty) {
            // 这个异常现在主要由 _extractTextareaContent 内部抛出
            throw Exception("AI返回了空内容或解析后内容为空。");
          }
          
          rewrittenContent.writeln(content);

          _logger.info('[章节重写] 第 ${i + 1} 段完成。当前总字数: ${rewrittenContent.length}');
          success = true;
          break; // 成功，跳出内部重试循环

        } catch (e, s) {
          _logger.error('[章节重写] 续写第 ${i + 1} 段失败 (尝试 ${j + 1}/$maxContentRetries)。', e, s);
          if (j == maxContentRetries - 1) { // 如果是最后一次尝试
            throw Exception('续写章节失败，请重试。');
          }
        }
      }
      if (!success) {
          // 如果一个段落最终失败，则停止整个过程 (理论上不会执行到这里，因为内循环会抛出异常)
          throw Exception('续写章节时发生严重错误。');
      }
    }


    // 4. 返回结果
    _logger.success('[章节重写] 全部段落已完成。');
    return (newTitle: newTitle, newContent: rewrittenContent.toString().trim());
  }
}