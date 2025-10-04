// lib/services/task_executor/image_to_video_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:pool/pool.dart';
import 'package:path/path.dart' as p;
import 'package:tiktoken/tiktoken.dart';

import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../cache_manager/cache_manager.dart';
import '../llm_service/llm_service.dart';
import '../prompt_builder/llm_prompt_builder.dart';
import '../task_manager/task_manager_service.dart';
import '../../base/log/log_service.dart';
import '../video_service/video_service.dart';

/// 内部子任务的数据结构，封装了执行单个视频生成任务所需的信息。
class _ExecutionSubTask {
  final VideoGenerationTaskChunk chunk;
  final Book book;

  _ExecutionSubTask({
    required this.chunk,
    required this.book,
  });
}

class ImageToVideoGeneratorService {
  ImageToVideoGeneratorService._();
  static final ImageToVideoGeneratorService instance = ImageToVideoGeneratorService._();

  // 依赖的服务
  final CacheManager _cacheManager = CacheManager();
  final ConfigService _configService = ConfigService();
  final LlmService _llmService = LlmService.instance;
  final VideoService _videoService = VideoService.instance;
  final LlmPromptBuilder _llmPromptBuilder = LlmPromptBuilder(ConfigService());
  final LogService _logger = LogService.instance;

  Future<void> generateForBook(
    Book book, {
    required CancellationToken cancellationToken,
    required Future<void> Function(double, VideoGenerationTaskChunk) onProgressUpdate,
    required bool Function() isPaused,
  }) async {
    _logger.info("🚀 开始为书籍《${book.title}》生成视频...");

    // 1. 重新加载书架，获取最新的任务区块状态
    final bookshelf = await _cacheManager.loadBookshelf();
    final entry = bookshelf.firstWhere((e) => e.id == book.id);
    final allChunks = entry.videoGenerationTaskChunks;

    // 2. 筛选出需要执行的任务
    final tasksToRun = allChunks
        .where((c) => c.status == ChunkStatus.pending || c.status == ChunkStatus.failed)
        .map((chunk) => _ExecutionSubTask(chunk: chunk, book: book))
        .toList();
    
    _logger.info("📖 发现 ${allChunks.length} 个视频生成子任务，其中 ${tasksToRun.length} 个需要执行。");
    
    // 3. 并发执行所有待处理任务
    await _executeTasksConcurrently(
      tasksToRun,
      allChunks.length,
      cancellationToken,
      onProgressUpdate,
      isPaused,
    );

    // 检查任务是否在执行过程中被取消
    if (cancellationToken.isCanceled) throw Exception('视频生成任务已取消');

    // 4. 所有任务完成后，保存更新后的书籍数据
    try {
      _logger.info("💾 正在将更新后的书籍数据保存到缓存...");
      await _cacheManager.saveBookDetail(book);
      _logger.success("✅ 书籍数据保存成功！");
    } catch (e, s) {
      _logger.error("❌ 保存书籍数据失败", e, s);
      throw Exception('Failed to save book details after video generation: $e');
    }

    _logger.success("\n🎉 《${book.title}》所有视频生成任务执行完毕。");
  }

  /// 使用并发池并发执行所有子任务
  Future<void> _executeTasksConcurrently(
    List<_ExecutionSubTask> tasksToRun,
    int totalChunks,
    CancellationToken cancellationToken,
    Future<void> Function(double, VideoGenerationTaskChunk) onProgressUpdate,
    bool Function() isPaused,
  ) async {
    if (totalChunks == 0) return;

    // 从配置中读取激活的视频API，并获取其并发限制
    final videoApi = _configService.getActiveVideoApi();
    final videoConcurrency = videoApi.concurrencyLimit ?? 1;
    final pool = Pool(max(1, videoConcurrency));
    _logger.info("🛠️  启动视频生成任务池，最大并发数: $videoConcurrency (来自视频API '${videoApi.name}')");

    int completedTasks = totalChunks - tasksToRun.length;
    final List<Future> futures = [];

    for (final task in tasksToRun) {
      final future = pool.withResource(() async {
        if (cancellationToken.isCanceled) return;

        while (isPaused()) {
          if (cancellationToken.isCanceled) return;
          await Future.delayed(const Duration(seconds: 1));
        }
        
        task.chunk.status = ChunkStatus.running;
        await onProgressUpdate(completedTasks / totalChunks, task.chunk);
        
        final success = await _processChunk(task, cancellationToken);
        
        task.chunk.status = success ? ChunkStatus.completed : ChunkStatus.failed;

      }).then((_) async {
        if (!cancellationToken.isCanceled) {
          if (task.chunk.status == ChunkStatus.completed) {
            completedTasks++;
          }
          final progress = completedTasks / totalChunks;
          await onProgressUpdate(progress, task.chunk);
        }
      });
      futures.add(future);
    }
    
    await Future.wait(futures);
    // 再次检查取消状态
    if (cancellationToken.isCanceled) throw Exception('任务已取消');
  }

  /// 处理单个视频生成任务区块
  Future<bool> _processChunk(_ExecutionSubTask task, CancellationToken cancellationToken) async {
    final chunk = task.chunk;
    final book = task.book;

    try {
      // 检查任务是否已取消
      if (cancellationToken.isCanceled) return false;

      final chapter = book.chapters.firstWhere((c) => c.id == chunk.chapterId);
      final line = chapter.lines.firstWhere((l) => l.id == chunk.lineId);
      final imagePath = chunk.sourceImagePath;
      
      final bookCacheDir = p.dirname(book.cachedPath);
      final saveDir = p.join(bookCacheDir, 'video');

      _logger.info("  ⚡️ [视频子任务] 开始处理图片: $imagePath");

      // 1. 兼容解析 sceneDescription，获取静态场景描述
      final (sceneDescription, _) = _parseSceneDescription(line.sceneDescription);
      if (sceneDescription.isEmpty) {
        _logger.warn("  [视频子任务] ⚠️ 该插图没有场景描述，无法生成视频。跳过此任务。");
        return false; // 标记为失败，但不是致命错误
      }

      // 2. 提取插图所在位置的上下文
      _logger.info('  [视频生成] 正在提取约4000 tokens的上下文...');
      final contextText = _extractContextAroundLine(line, chapter, 4000);

      // 3. 调用 LLM 将绘画提示词和上下文转换为更适合视频生成的动态化提示词
      _logger.info('  [视频生成] 调用LLM生成视频专用提示词...');
      final videoPrompt = await _generateAndParseVideoPrompt(sceneDescription, contextText, cancellationToken);

      if (cancellationToken.isCanceled) return false;

      if (videoPrompt.isEmpty) {
        _logger.error("  [视频生成] ❌ LLM 未能生成有效的视频提示词。");
        return false; // 标记此区块处理失败
      }
      _logger.info("  [视频生成] ✅ LLM生成成功，视频提示词: $videoPrompt");

      // 4. 从配置中获取视频生成参数
      final resolution = _configService.getSetting<String>('video_gen_resolution', '720p');
      final duration = _configService.getSetting<int>('video_gen_duration', 5);
      final activeVideoApi = _configService.getActiveVideoApi();

      // 5. 使用视频API的速率限制器
      final videoRateLimiter = _configService.getRateLimiterForApi(activeVideoApi);
      _logger.info("  [视频生成] 等待速率限制器 (RPM: ${activeVideoApi.rpm})...");
      await videoRateLimiter.acquire();
      _logger.info("  [视频生成] 已获取速率令牌，并发槽位已就绪，正在执行API请求...");

      if (cancellationToken.isCanceled) return false;

      // 6. 调用视频服务生成视频
      final videoPaths = await _videoService.generateVideo(
        positivePrompt: videoPrompt,
        saveDir: saveDir,
        count: 1,
        resolution: resolution,
        duration: duration,
        referenceImagePath: imagePath,
        apiConfig: activeVideoApi,
      );

      if (cancellationToken.isCanceled) return false;
      
      // 7. 将生成的视频路径保存到 book model
      if (videoPaths != null && videoPaths.isNotEmpty) {
        _logger.success('  [视频生成] ✅ 成功！路径: $videoPaths');
        chapter.addVideosToLine(line.id, videoPaths);
      } else {
        _logger.error("  [视频生成] ❌ 失败！视频服务未能生成视频。");
        return false;
      }
      
      // 注意：此处不再保存book，统一在generateForBook末尾保存，减少IO操作
      _logger.info("  [视频子任务] ✅ 子任务 ${chunk.id} 完成。");
      return true;

    } catch (e, s) {
      if (cancellationToken.isCanceled || e.toString().contains('canceled')) {
        _logger.warn("  [视频子任务取消]");
      } else {
        _logger.error("  ❌ [视频子任务失败] Chunk ${chunk.id}", e, s);
      }
      return false;
    }
  }

  /// 调用LLM服务生成视频提示词，并解析返回的JSON数据。
  Future<String> _generateAndParseVideoPrompt(String sceneDescription, String contextText, CancellationToken cancellationToken) async {
    final (systemPrompt, messages) = _llmPromptBuilder.buildForVideoPrompt(
      sceneDescription: sceneDescription,
      contextText: contextText,
    );
    final activeApi = _configService.getActiveLanguageApi();
    final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);

    // 最多尝试2次
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (cancellationToken.isCanceled) throw Exception('任务已取消');
        if (attempt > 0) {
          _logger.warn("    [LLM] 🔄 响应解析失败，正在进行第 $attempt 次重试...");
        }

        await llmRateLimiter.acquire();
        _logger.info("    [LLM] 已获取到速率令牌，正在发送请求... (尝试 ${attempt + 1}/2)");

        final llmResponse = await _llmService.requestCompletion(
          systemPrompt: systemPrompt,
          messages: messages,
          apiConfig: activeApi,
        );
        _logger.info("    [LLM] LLM 响应内容: $llmResponse");

        final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
        final jsonString = jsonMatch?.group(1) ?? llmResponse;
        final data = jsonDecode(jsonString);

        if (data is Map<String, dynamic>) {
          final prompt = data['prompt'] as String?;
          if (prompt != null && prompt.isNotEmpty) {
            return prompt; // 成功解析并返回
          }
        }
        _logger.error('    [LLM] ❌ LLM 响应JSON格式错误或缺少 "prompt" 字段。');
      } catch (e, s) {
        _logger.error('    [LLM] ❌ 处理LLM响应时失败 (尝试 ${attempt + 1}/2)', e, s);
      }
    }
    return ""; // 两次都失败则返回空字符串
  }

  /// 以目标行为中心，提取指定token数量的上下文 (从SingleVideoExecutor复制而来)
  String _extractContextAroundLine(LineStructure targetLine, ChapterStructure chapter, int maxTokens) {
    final encoding = encodingForModel("gpt-4");
    final lines = chapter.lines;
    final targetIndex = lines.indexOf(targetLine);
    if (targetIndex == -1) return targetLine.text;

    List<String> contextLines = [targetLine.text];
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

  /// 解析sceneDescription，兼容新旧格式 (从SingleVideoExecutor复制而来)
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