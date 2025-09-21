// lib/services/task_executor/illustration_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:pool/pool.dart';

import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import '../../models/character_card_model.dart';
import '../cache_manager/cache_manager.dart';
import '../drawing_service/drawing_service.dart';
import '../llm_service/llm_service.dart';
import '../task_manager/task_manager_service.dart';
import '../prompt_builder/draw_prompt_builder.dart';
import '../prompt_builder/llm_prompt_builder.dart';


/// 内部子任务的数据结构，封装了执行单个任务块所需的所有信息。
class _ExecutionSubTask {
  final IllustrationTaskChunk chunk; // 任务区块元数据
  final ChapterStructure chapter; // 所属章节的结构化数据
  final List<LineStructure> lineChunk; // 区块对应的具体文本行
  final String saveDir; // 图片保存目录

  _ExecutionSubTask({
    required this.chunk,
    required this.chapter,
    required this.lineChunk,
    required this.saveDir,
  });
}

class IllustrationGeneratorService {
  final LlmPromptBuilder _llmPromptBuilder;
  final DrawPromptBuilder _drawPromptBuilder;
  
  IllustrationGeneratorService._() 
    : _configService = ConfigService(),
      _llmPromptBuilder = LlmPromptBuilder(ConfigService()),
      _drawPromptBuilder = DrawPromptBuilder(ConfigService());

  static final IllustrationGeneratorService instance = IllustrationGeneratorService._();

  // 依赖的服务实例
  final LlmService _llmService = LlmService.instance;
  final DrawingService _drawingService = DrawingService.instance;
  final ConfigService _configService;

  /// 为指定书籍生成插图的主流程方法。
  Future<void> generateForBook(
    Book book, {
    required CancellationToken cancellationToken, // 用于取消任务的令牌
    required Future<void> Function(double, IllustrationTaskChunk) onProgressUpdate, // 进度更新回调
    required bool Function() isPaused, // 检查任务是否暂停的回调
  }) async {

    print("🚀 开始为书籍《${book.title}》生成插图...");

    // 1. 从缓存重新加载最新的书架条目，以获取最新的任务区块状态
    final bookshelf = await CacheManager().loadBookshelf();
    final entry = bookshelf.firstWhere((e) => e.id == book.id);
    final allChunks = entry.taskChunks;

    // 2. 准备执行任务，筛选出需要处理的任务块
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(book.id, 'illustrations');
    final List<_ExecutionSubTask> executionTasks = [];
    
    for (final chunk in allChunks) {
      // 只处理待处理或失败的任务，实现断点续传
      if (chunk.status == ChunkStatus.pending || chunk.status == ChunkStatus.failed) {
        final chapter = book.chapters.firstWhere((c) => c.id == chunk.chapterId, // <--- 使用ID进行匹配
            orElse: () => throw Exception('找不到章节ID: ${chunk.chapterId}')); // 添加一个错误处理以防万一
        // 根据区块的起止行ID，筛选出对应的文本行
        final lines = chapter.lines.where((l) => l.id >= chunk.startLineId && l.id <= chunk.endLineId).toList();
        executionTasks.add(_ExecutionSubTask(
          chunk: chunk,
          chapter: chapter,
          lineChunk: lines,
          saveDir: illustrationsDir.path
        ));
      }
    }

    print("📖 发现 ${allChunks.length} 个子任务，其中 ${executionTasks.length} 个需要执行。");

    // 3. 并发执行所有待处理的任务
    await _executeTasksConcurrently(
      executionTasks, allChunks.length,
      cancellationToken, onProgressUpdate, isPaused
    );

    // 检查任务是否在执行过程中被取消
    if (cancellationToken.isCanceled) throw Exception('任务已取消');

    // 4. 所有任务完成后，保存更新后的书籍数据和书架状态
    try {
      print("💾 正在将更新后的书籍数据保存到缓存...");
      await CacheManager().saveBookDetail(book); // 保存被修改的 book 对象
      print("✅ 书籍数据保存成功！");
    } catch (e) {
      print("❌ 保存书籍数据失败: $e");
      // 即使保存失败，也应该抛出异常，让 TaskManager 知道任务的最后一步出错了
      throw Exception('Failed to save book details after illustration generation: $e');
    }


    print("\n🎉 《${book.title}》所有插图任务执行完毕！");
  }

  /// 使用两个独立的并发池（LLM池和绘图池）来并发执行所有子任务。
  Future<void> _executeTasksConcurrently(
    List<_ExecutionSubTask> tasksToRun,
    int totalChunks,
    CancellationToken cancellationToken,
    Future<void> Function(double, IllustrationTaskChunk) onProgressUpdate,
    bool Function() isPaused,
  ) async {
    if (totalChunks == 0) return;

    // LLM池 1: 用于 LLM 请求（场景分析和提示词生成）
    final llmApi = _configService.getActiveLanguageApi();
    final llmConcurrency = llmApi.concurrencyLimit ?? 1; // 从配置读取LLM并发数
    final llmPool = Pool(max(1, llmConcurrency));
    print("🛠️  启动 LLM 任务池，最大并发数: $llmConcurrency (来自语言API '${llmApi.name}')");

    // draw池 2: 用于绘图请求（图片生成）
    final drawingApi = _configService.getActiveDrawingApi();
    final drawingConcurrency = drawingApi.concurrencyLimit ?? 1; // 从配置读取绘图并发数
    final drawingPool = Pool(max(1, drawingConcurrency));
    print("🎨  启动绘图任务池，最大并发数: $drawingConcurrency (来自绘图API '${drawingApi.name}')");

    // 已完成任务数，用于计算总进度
    int completedTasks = totalChunks - tasksToRun.length;

    final List<Future> llmFutures = [];
    for (final task in tasksToRun) {
      // 使用LLM池来限制 "分析文本->生成所有绘图任务" 这个完整流程的并发数
      final future = llmPool.withResource(() async {
        if (cancellationToken.isCanceled) return;

        // 检查并等待暂停状态
        while (isPaused()) {
          if (cancellationToken.isCanceled) return;
          await Future.delayed(const Duration(seconds: 1));
        }
        
        // 更新区块状态为 "运行中" 并通知UI
        task.chunk.status = ChunkStatus.running;
        await onProgressUpdate(completedTasks / totalChunks, task.chunk);
        
        // 核心处理逻辑，将绘图池传入，供内部调度
        final success = await _processChunkForImages(task, cancellationToken, isPaused, drawingPool);

        // 根据处理结果更新区块状态
        task.chunk.status = success ? ChunkStatus.completed : ChunkStatus.failed;

      }).then((_) async {
        // 当一个子任务（包括其所有绘图）完成后
        if (!cancellationToken.isCanceled) {
          if (task.chunk.status == ChunkStatus.completed) {
            completedTasks++;
          }
          final progress = completedTasks / totalChunks;
          await onProgressUpdate(progress, task.chunk); // 更新总进度和区块状态
        }
      });
      llmFutures.add(future);
    }
    
    // 等待所有子任务流程完成
    await Future.wait(llmFutures);
    if (cancellationToken.isCanceled) throw Exception('任务已取消');
  }

  /// 处理单个任务区块的完整流程：调用LLM分析 -> 并发执行绘图。
  Future<bool> _processChunkForImages(
    _ExecutionSubTask task, 
    CancellationToken cancellationToken, 
    bool Function() isPaused,
    Pool drawingPool // 接收外部传入的绘图池
  ) async {
    print("  ⚡️ [子任务启动] ${task.chunk.id} 需要AI挑选 ${task.chunk.scenesToGenerate} 个场景...");
    final textContent = task.lineChunk.map((l) => "${l.id}: ${l.text}").join('\n');

    try {
      // 调用 LLM 生成绘图数据 (此调用受外层 llmPool 的并发限制)
      final illustrationsData = await _generateAndParseIllustrationData(textContent, task.chunk.scenesToGenerate, cancellationToken);
      if (cancellationToken.isCanceled) return false;

      if (illustrationsData.isEmpty) {
        print("    [LLM] ❌ 未能从LLM响应中解析出有效的绘图项（重试后依然失败）。");
        return false;
      }
      print("    [LLM] ✅ 成功解析，找到 ${illustrationsData.length} 个绘图项。现在提交到绘图队列...");

      // 查找带参考图的角色
      final plainTextContent = task.lineChunk.map((l) => l.text).join('\n');
      String? referenceImageForTask;
      final allCardsJson = _configService.getSetting<List<dynamic>>('drawing_character_cards', []);
      final allCards = allCardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
      
      for (final card in allCards) {
        final characterNameToMatch = card.characterName.isNotEmpty ? card.characterName : card.name;
        if (characterNameToMatch.isNotEmpty && plainTextContent.contains(characterNameToMatch)) {
          final imagePath = card.referenceImagePath;
          final imageUrl = card.referenceImageUrl;
          if ((imagePath != null && imagePath.isNotEmpty) || (imageUrl != null && imageUrl.isNotEmpty)) {
            // 优先使用本地路径，如果不存在则使用URL
            referenceImageForTask = imagePath ?? imageUrl;
            print("    [角色匹配] ✅ 在文本中找到角色 '$characterNameToMatch'，将使用参考图进行生成: $referenceImageForTask");
            break; // 找到第一个就停止
          }
        }
      }

      // 将每个绘图任务提交到 drawingPool，实现绘图的并发执行
      final List<Future> drawingFutures = [];
      for (final itemData in illustrationsData) {
        final future = drawingPool.withResource(() async {
          if (cancellationToken.isCanceled) return;
          
          // 在每个绘图任务开始前也检查暂停状态
          while (isPaused()) {
             await Future.delayed(const Duration(seconds: 1));
             if (cancellationToken.isCanceled) return;
          }

          // 实际执行绘图和保存操作
          await _generateAndSaveImagesForScene(
            itemData, 
            task.chapter, 
            task.saveDir, 
            cancellationToken,
            referenceImagePath: referenceImageForTask, // 传入找到的参考图
          );
        });
        drawingFutures.add(future);
      }
      
      // 等待这个区块内的所有绘图任务完成
      await Future.wait(drawingFutures);

      return true; // 整个区块处理成功
    } catch (e) {
      if (cancellationToken.isCanceled || e.toString().contains('canceled')) {
        print("  [子任务取消]");
      } else {
        print("  ❌ [子任务失败] ${task.chunk.id} 处理时出错: $e");
      }
      return false; // 区块处理失败
    }
  }

  /// 调用LLM服务生成场景描述和提示词，并解析返回的JSON数据。
  Future<List<Map<String, dynamic>>> _generateAndParseIllustrationData(String textContent, int numScenes, CancellationToken cancellationToken) async {
    final (systemPrompt, messages) = _llmPromptBuilder.buildForSceneDiscovery(textContent: textContent, numScenes: numScenes);
    final activeApi = _configService.getActiveLanguageApi();
    final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);

    // 最多尝试2次（1次原始 + 1次重试）
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (cancellationToken.isCanceled) throw Exception('任务已取消');

        if (attempt > 0) {
          print("    [LLM] 🔄 响应解析失败，正在进行第 $attempt 次重试...");
        }

        // 在每次尝试前都等待获取一个“令牌”
        await llmRateLimiter.acquire();
        print("    [LLM] 已获取到速率令牌，正在发送请求... (尝试 ${attempt + 1}/2)");
        
        // 执行LLM请求
        final llmResponse = await _llmService.requestCompletion(
          systemPrompt: systemPrompt,
          messages: messages,
          apiConfig: activeApi,
        );
        print("    [LLM] LLM 响应内容: $llmResponse");

        // 从返回的文本中提取JSON部分
        final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
        final jsonString = jsonMatch?.group(1) ?? llmResponse;
        
        // 直接将JSON字符串解析为List
        final data = jsonDecode(jsonString);

        // 检查返回的数据是否为List类型
        if (data is List) {
          // 成功解析，立即返回结果
          return data.cast<Map<String, dynamic>>();
        } else {
          print('    [LLM] ❌ LLM 响应JSON格式错误: 响应不是一个有效的JSON数组。');
          // 继续循环进行重试
        }
      } catch (e) {
        print('    [LLM] ❌ 处理LLM响应时失败 (尝试 ${attempt + 1}/2): $e');
        // 捕获异常后，循环将继续进行下一次尝试
      }
    }

    // 如果两次尝试都失败了，则返回空列表
    return [];
  }

  /// 调用绘图服务为单个场景生成并保存图片。
  Future<void> _generateAndSaveImagesForScene(
    Map<String, dynamic> illustrationData, 
    ChapterStructure chapter, 
    String saveDir, 
    CancellationToken cancellationToken,
    { String? referenceImagePath } // 新增可选参数
  ) async {
    final llmPrompt = illustrationData['prompt'] as String?;
    final lineId = illustrationData['insertion_line_number'] as int?; 
    final sceneDescription = illustrationData['scene_description'] as String?;

    if (llmPrompt == null || lineId == null) return;
    
    if (cancellationToken.isCanceled) throw Exception('任务已取消');

    // 从设置中读取每个场景生成几张图片、图片尺寸等配置
    final imagesPerScene = _configService.getSetting<int>('image_gen_images_per_scene', 2);
    final sizeString = _configService.getSetting<String>('image_gen_size', appDefaultConfigs['image_gen_size']);
    final sizeParts = sizeString.split('*').map((e) => int.tryParse(e) ?? 1024).toList();
    final width = sizeParts[0];
    final height = sizeParts[1];

    // CHANGED: 更新日志，使用 lineId。
    print("      [绘图] 开始为《${chapter.title}》ID为 $lineId 的行生成 $imagesPerScene 张插图 (尺寸: ${width}x${height})...");
    print("      - 场景: ${sceneDescription ?? '无'}");

    // 使用新的Builder结合LLM生成的提示词和用户配置的固定提示词，构建最终的绘图提示
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: llmPrompt);
    print("      - 正面提示词: $positivePrompt");
    print("      - 负面提示词: $negativePrompt");

    final activeApi = _configService.getActiveDrawingApi();
    
    // Pool控制并发数，RateLimiter控制请求频率
    final drawingRateLimiter = _configService.getRateLimiterForApi(activeApi);
    // 已修改：更新日志输出
    print("      [绘图] 等待速率限制器 (RPM: ${activeApi.rpm})...");
    await drawingRateLimiter.acquire(); // 等待获取速率令牌
    print("      [绘图] 已获取速率令牌，并发槽位已就绪，正在执行API请求...");

    // 调用绘图服务生成图片
    final imagePaths = await _drawingService.generateImages(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      saveDir: saveDir,
      count: imagesPerScene,
      width: width,
      height: height,
      apiConfig: activeApi,
      referenceImagePath: referenceImagePath, // 向下传递参考图路径
    );

    if (cancellationToken.isCanceled) return; // 检查任务是否在绘图过程中被取消

    // 如果成功生成图片，将其路径关联到对应的文本行
    if (imagePaths != null && imagePaths.isNotEmpty) {
      chapter.addIllustrationsToLine(lineId, imagePaths, positivePrompt);
      print("      [绘图] ✅ 成功！${imagePaths.length} 张图片已保存并关联。");
      for (final path in imagePaths) {
        print("        - $path");
      }
    } else {
      print("      [绘图] ❌ 失败！未能生成或保存任何图片。");
    }
  }
}