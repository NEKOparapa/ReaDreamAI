// lib/services/task_executor/illustration_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:pool/pool.dart';

import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';
import '../../base/default_configs.dart';
import '../cache_manager/cache_manager.dart';
import '../drawing_service/drawing_service.dart';
import '../llm_service/llm_service.dart';
import '../task_manager/task_manager_service.dart';
import '../prompt_builder/draw_prompt_builder.dart';
import '../prompt_builder/llm_prompt_builder.dart';
import '../../base/log/log_service.dart';

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

/// 插图生成服务 (单例)
class IllustrationGeneratorService {
  final LlmPromptBuilder _llmPromptBuilder;
  final DrawPromptBuilder _drawPromptBuilder;

  // 私有构造函数，用于实现单例模式
  IllustrationGeneratorService._()
      : _configService = ConfigService(),
        _llmPromptBuilder = LlmPromptBuilder(ConfigService()),
        _drawPromptBuilder = DrawPromptBuilder(ConfigService());

  // 提供全局唯一的服务实例
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
    LogService.instance.info("🚀 开始为书籍《${book.title}》生成插图...");

    // 1. 从缓存重新加载最新的书架条目，以获取最新的任务区块状态
    final bookshelf = await CacheManager().loadBookshelf();
    final entry = bookshelf.firstWhere((e) => e.id == book.id);
    final allChunks = entry.taskChunks;

    // 2. 准备执行任务，筛选出需要处理的任务块
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(book.id, 'illustrations');
    final List<_ExecutionSubTask> executionTasks = []; // 待执行的任务列表

    // 遍历所有任务区块
    for (final chunk in allChunks) {
      // 只处理待处理或失败的任务，实现断点续传
      if (chunk.status == ChunkStatus.pending || chunk.status == ChunkStatus.failed) {
        // 根据区块中的 chapterId 找到对应的章节数据
        final chapter = book.chapters.firstWhere((c) => c.id == chunk.chapterId,
            orElse: () => throw Exception('找不到章节ID: ${chunk.chapterId}'));
        // 根据区块的起止行ID，筛选出对应的文本行
        final lines = chapter.lines.where((l) => l.id >= chunk.startLineId && l.id <= chunk.endLineId).toList();
        // 创建一个内部执行任务对象
        executionTasks.add(_ExecutionSubTask(
            chunk: chunk,
            chapter: chapter,
            lineChunk: lines,
            saveDir: illustrationsDir.path));
      }
    }

    LogService.instance.info("📖 发现 ${allChunks.length} 个子任务，其中 ${executionTasks.length} 个需要执行。");

    // 3. 并发执行所有待处理的任务
    await _executeTasksConcurrently(
        executionTasks, allChunks.length,
        cancellationToken, onProgressUpdate, isPaused);

    // 检查任务是否在执行过程中被取消
    if (cancellationToken.isCanceled) throw Exception('任务已取消');

    // 4. 所有任务完成后，保存更新后的书籍数据和书架状态
    try {
      LogService.instance.info("💾 正在将更新后的书籍数据保存到缓存...");
      await CacheManager().saveBookDetail(book); // 保存被修改的 book 对象
      LogService.instance.success("✅ 书籍数据保存成功！");
    } catch (e, s) {
      LogService.instance.error("❌ 保存书籍数据失败", e, s);
      // 即使保存失败，也应该抛出异常，让 TaskManager 知道任务的最后一步出错了
      throw Exception('Failed to save book details after illustration generation: $e');
    }

    LogService.instance.success("\n🎉 《${book.title}》所有插图任务执行完毕！");
  }

  /// 使用两个独立的并发池（LLM池和绘图池）来并发执行所有子任务。
  Future<void> _executeTasksConcurrently(
    List<_ExecutionSubTask> tasksToRun, // 需要运行的任务列表
    int totalChunks, // 任务总数（用于计算进度）
    CancellationToken cancellationToken,
    Future<void> Function(double, IllustrationTaskChunk) onProgressUpdate,
    bool Function() isPaused,
  ) async {
    // 如果没有任务块，直接返回
    if (totalChunks == 0) return;

    // LLM池: 用于限制语言模型API的并发请求数（例如场景分析和提示词生成）
    final llmApi = _configService.getActiveLanguageApi();
    final llmConcurrency = llmApi.concurrencyLimit ?? 1; // 从配置读取LLM并发数，默认为1
    final llmPool = Pool(max(1, llmConcurrency)); // 创建并发池，最小并发为1
    LogService.instance.info("🛠️  启动 LLM 任务池，最大并发数: $llmConcurrency (来自语言API '${llmApi.name}')");

    // 绘图池: 用于限制绘图API的并发请求数（图片生成）
    final drawingApi = _configService.getActiveDrawingApi();
    final drawingConcurrency = drawingApi.concurrencyLimit ?? 1; // 从配置读取绘图并发数，默认为1
    final drawingPool = Pool(max(1, drawingConcurrency)); // 创建并发池，最小并发为1
    LogService.instance.info("🎨  启动绘图任务池，最大并发数: $drawingConcurrency (来自绘图API '${drawingApi.name}')");

    // 已完成任务数，用于计算总进度。初始值为已完成的任务块数量。
    int completedTasks = totalChunks - tasksToRun.length;

    // 为每个待执行的任务创建一个 Future
    final List<Future> llmFutures = [];
    for (final task in tasksToRun) {
      // 使用 LLM 池来限制并发。每个 'withResource' 会占用一个并发槽位，直到其内部的 async 函数执行完毕。
      final future = llmPool.withResource(() async {
        // 任务开始前检查是否已取消
        if (cancellationToken.isCanceled) return;

        // 检查并等待暂停状态。如果isPaused()为true，则循环等待。
        while (isPaused()) {
          if (cancellationToken.isCanceled) return;
          await Future.delayed(const Duration(seconds: 1)); // 每秒检查一次
        }

        // 更新区块状态为 "运行中" 并通过回调通知UI
        task.chunk.status = ChunkStatus.running;
        await onProgressUpdate(completedTasks / totalChunks, task.chunk);

        // 核心处理逻辑：处理单个任务区块，将绘图池传入，供内部调度绘图任务
        final success = await _processChunkForImages(task, cancellationToken, isPaused, drawingPool);

        // 根据处理结果更新区块状态
        task.chunk.status = success ? ChunkStatus.completed : ChunkStatus.failed;
      }).then((_) async {
        // 当一个子任务（包括其所有内部的绘图任务）完成后，执行此回调
        if (!cancellationToken.isCanceled) {
          // 如果任务成功完成，增加已完成任务计数
          if (task.chunk.status == ChunkStatus.completed) {
            completedTasks++;
          }
          // 计算并更新总进度
          final progress = completedTasks / totalChunks;
          await onProgressUpdate(progress, task.chunk); // 更新总进度和区块状态
        }
      });
      llmFutures.add(future);
    }

    // 等待所有通过 llmPool 调度的任务全部完成
    await Future.wait(llmFutures);
    // 再次检查取消状态
    if (cancellationToken.isCanceled) throw Exception('任务已取消');
  }

  /// 处理单个任务区块的完整流程：调用LLM分析 -> 并发执行绘图。
  Future<bool> _processChunkForImages(
    _ExecutionSubTask task,
    CancellationToken cancellationToken,
    bool Function() isPaused,
    Pool drawingPool, // 接收外部传入的绘图池，用于并发控制绘图任务
  ) async {
    LogService.instance.info("  ⚡️ [子任务启动] ${task.chunk.id} 需要AI挑选 ${task.chunk.scenesToGenerate} 个场景...");
    // 将区块内的文本行拼接成一个字符串，供LLM分析
    final textContent = task.lineChunk.map((l) => "${l.id}: ${l.text}").join('\n');

    try {
      // 1. 调用 LLM 生成绘图所需的数据 (此调用受外层 llmPool 的并发限制)
      final illustrationsData = await _generateAndParseIllustrationData(textContent, task.chunk.scenesToGenerate, cancellationToken);
      if (cancellationToken.isCanceled) return false;

      // 如果LLM未能返回有效的绘图数据
      if (illustrationsData.isEmpty) {
        LogService.instance.error("    [LLM] ❌ 未能从LLM响应中解析出有效的绘图项（重试后依然失败）。");
        return false; // 标记此区块处理失败
      }
      LogService.instance.info("    [LLM] ✅ 成功解析，找到 ${illustrationsData.length} 个绘图项。现在提交到绘图队列...");
      
      // 2. 将每个绘图任务提交到 drawingPool，实现绘图的并发执行
      final List<Future> drawingFutures = [];
      for (final itemData in illustrationsData) {
        // 使用绘图池来并发执行每一个绘图任务
        final future = drawingPool.withResource(() async {
          if (cancellationToken.isCanceled) return;

          // 在每个绘图任务开始前也检查暂停状态
          while (isPaused()) {
            await Future.delayed(const Duration(seconds: 1));
            if (cancellationToken.isCanceled) return;
          }
          
          // 从LLM返回的数据中提取登场角色
          final appearingCharacters = (itemData['appearing_characters'] as List<dynamic>? ?? []).cast<String>();
          
          // 根据登场角色查找参考图
          final referenceImagePath = _drawPromptBuilder.findReferenceImageForCharacters(appearingCharacters);
          if (referenceImagePath != null) {
            LogService.instance.info("    [角色匹配] ✅ 场景将使用角色 ${appearingCharacters.join(',')} 的参考图: $referenceImagePath");
          }

          // 实际执行绘图和保存操作
          await _generateAndSaveImagesForScene(
            itemData,
            task.chapter,
            task.saveDir,
            cancellationToken,
            referenceImagePath: referenceImagePath, // 传入为该特定场景找到的参考图
          );
        });
        drawingFutures.add(future);
      }

      // 等待这个区块内的所有绘图任务完成
      await Future.wait(drawingFutures);

      return true; // 整个区块处理成功
    } catch (e, s) {
      if (cancellationToken.isCanceled || e.toString().contains('canceled')) {
        LogService.instance.warn("  [子任务取消]");
      } else {
        LogService.instance.error("  ❌ [子任务失败] ${task.chunk.id} 处理时出错", e, s);
      }
      return false; // 区块处理失败
    }
  }

  /// 调用LLM服务生成场景描述和提示词，并解析返回的JSON数据。
  Future<List<Map<String, dynamic>>> _generateAndParseIllustrationData(String textContent, int numScenes, CancellationToken cancellationToken) async {
    // 构造LLM请求的提示
    final (systemPrompt, messages) = _llmPromptBuilder.buildForSceneDiscovery(textContent: textContent, numScenes: numScenes);
    final activeApi = _configService.getActiveLanguageApi();
    // 获取对应API的速率限制器
    final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);

    // 最多尝试3次（1次原始 + 1次重试）
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (cancellationToken.isCanceled) throw Exception('任务已取消');

        if (attempt > 0) {
          LogService.instance.warn("    [LLM] 🔄 响应解析失败，正在进行第 $attempt 次重试...");
        }

        // 在每次尝试前都等待获取一个“令牌”，以符合API的速率限制
        await llmRateLimiter.acquire();
        LogService.instance.info("    [LLM] 已获取到速率令牌，正在发送请求... (尝试 ${attempt + 1}/3)");

        // 执行LLM请求
        final llmResponse = await _llmService.requestCompletion(
          systemPrompt: systemPrompt,
          messages: messages,
          apiConfig: activeApi,
        );
        LogService.instance.info("    [LLM] LLM 响应内容: $llmResponse");

        // 从返回的文本中用正则表达式提取JSON部分
        final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
        // 如果正则匹配失败，则假定整个响应就是JSON字符串
        final jsonString = jsonMatch?.group(1) ?? llmResponse;

        // 将JSON字符串解析为Dart对象
        final data = jsonDecode(jsonString);

        // 检查返回的数据是否为List类型
        if (data is List) {
          // 成功解析，将列表元素转换为指定类型并立即返回结果
          return data.cast<Map<String, dynamic>>();
        } else {
          LogService.instance.error('    [LLM] ❌ LLM 响应JSON格式错误: 响应不是一个有效的JSON数组。');
          // 继续循环进行重试
        }
      } catch (e, s) {
        LogService.instance.error('    [LLM] ❌ 处理LLM响应时失败 (尝试 ${attempt + 1}/3)', e, s);
        // 捕获异常后，循环将继续进行下一次尝试
      }
    }

    // 如果两次尝试都失败了，则返回空列表
    return [];
  }

  /// 调用绘图服务为单个场景生成并保存图片。
  Future<void> _generateAndSaveImagesForScene(
    Map<String, dynamic> illustrationData, // 从LLM获取的单个绘图任务数据
    ChapterStructure chapter,
    String saveDir,
    CancellationToken cancellationToken, {
    String? referenceImagePath,
  }) async {
    // 从绘图数据中提取关键信息
    final llmPrompt = illustrationData['prompt'] as String?;
    final lineId = illustrationData['insertion_line_number'] as int?;
    final sceneDescription = illustrationData['scene_description'] as String?;
    // 提取登场角色
    final appearingCharacters = (illustrationData['appearing_characters'] as List<dynamic>? ?? []).cast<String>();


    // 如果缺少必要的提示词或行号，则无法继续
    if (llmPrompt == null || lineId == null) return;

    // 检查取消状态
    if (cancellationToken.isCanceled) throw Exception('任务已取消');

    // 从设置中读取每个场景生成几张图片、图片尺寸等配置
    final imagesPerScene = _configService.getSetting<int>('image_gen_images_per_scene', 2);
    final sizeString = _configService.getSetting<String>('image_gen_size', appDefaultConfigs['image_gen_size']);
    final sizeParts = sizeString.split('*').map((e) => int.tryParse(e) ?? 1024).toList();
    final width = sizeParts[0];
    final height = sizeParts[1];

    LogService.instance.info("      [绘图] 开始为《${chapter.title}》ID为 $lineId 的行生成 $imagesPerScene 张插图 (尺寸: ${width}x${height})...");
    LogService.instance.info("      - 场景: ${sceneDescription ?? '无'}");
    if (appearingCharacters.isNotEmpty) {
       LogService.instance.info("      - 登场角色: ${appearingCharacters.join(', ')}");
    }

    // 使用 DrawPromptBuilder 结合LLM生成的提示词和用户配置的固定提示词，构建最终的绘图提示
    final (positivePrompt, negativePrompt) = _drawPromptBuilder.build(llmGeneratedPrompt: llmPrompt);
    LogService.instance.info("      - 正面提示词: $positivePrompt");
    LogService.instance.info("      - 负面提示词: $negativePrompt");

    final activeApi = _configService.getActiveDrawingApi();

    // Pool控制并发数，RateLimiter控制请求频率
    final drawingRateLimiter = _configService.getRateLimiterForApi(activeApi);
    LogService.instance.info("      [绘图] 等待速率限制器 (RPM: ${activeApi.rpm})...");
    await drawingRateLimiter.acquire(); // 等待获取速率令牌
    LogService.instance.info("      [绘图] 已获取速率令牌，并发槽位已就绪，正在执行API请求...");

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
      // 将生成的图片路径、原始绘画提示词和登场角色列表添加到 book model 对应的行数据中
      chapter.addIllustrationsToLine(lineId, imagePaths, llmPrompt, appearingCharacters);
      LogService.instance.success("      [绘图] ✅ 成功！${imagePaths.length} 张图片已保存并关联。");
      for (final path in imagePaths) {
        LogService.instance.info("        - $path");
      }
    } else {
      LogService.instance.error("      [绘图] ❌ 失败！未能生成或保存任何图片。");
    }
  }
}