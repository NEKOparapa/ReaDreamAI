// lib/services/task_executor/translation_generator_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';

import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';
import '../cache_manager/cache_manager.dart';
import '../llm_service/llm_service.dart';
import '../task_manager/task_manager_service.dart';
import '../../base/log/log_service.dart';

/// 翻译生成服务
class TranslationGeneratorService {
  // 私有构造函数，确保单例模式
  TranslationGeneratorService._();
  // 提供全局唯一的服务实例
  static final TranslationGeneratorService instance = TranslationGeneratorService._();

  // 依赖注入：获取其他服务的实例
  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();
  final CacheManager _cacheManager = CacheManager();

  /// 为指定书籍生成翻译内容
  Future<void> generateForBook(
    Book book, {
    required CancellationToken cancellationToken,
    required Future<void> Function(double, TranslationTaskChunk) onProgressUpdate,
    required bool Function() isPaused,
  }) async {
    LogService.instance.info("🚀 开始为书籍《${book.title}》生成翻译...");

    // 从缓存加载书架信息，以获取任务块的状态
    final bookshelf = await _cacheManager.loadBookshelf();

    // 找到当前书籍在书架中的条目和所有翻译任务块
    final entry = bookshelf.firstWhere((e) => e.id == book.id);
    final allChunks = entry.translationTaskChunks;

    // 筛选出需要执行的任务（状态为“待处理”或“失败”）
    final tasksToRun = allChunks.where((c) => c.status == ChunkStatus.pending || c.status == ChunkStatus.failed).toList();
    LogService.instance.info("📖 发现 ${allChunks.length} 个翻译子任务，其中 ${tasksToRun.length} 个需要执行。");
    
    // 获取当前激活的语言模型API配置
    final llmApi = _configService.getActiveLanguageApi();
    // 根据API配置设置并发限制，默认为1
    final llmConcurrency = llmApi.concurrencyLimit ?? 1;
    // 创建一个并发池（Pool），以控制同时向LLM发送请求的数量
    final llmPool = Pool(llmConcurrency);
    LogService.instance.info("🛠️ 启动翻译任务池，最大并发数: $llmConcurrency (来自语言API '${llmApi.name}')");

    // 初始化已完成任务计数器（包括之前已经完成的）
    int completedTasks = allChunks.length - tasksToRun.length;
    final List<Future> futures = [];

    // 遍历所有需要执行的任务块
    for (final chunk in tasksToRun) {
      // 使用并发池来执行每个任务
      final future = llmPool.withResource(() async {
        // 任务开始前，检查是否已被取消
        if (cancellationToken.isCanceled) return;

        // 检查暂停状态，如果暂停则在此处循环等待
        while (isPaused()) {
          if (cancellationToken.isCanceled) return;
          // 等待一秒后再次检查，避免CPU空转
          await Future.delayed(const Duration(seconds: 1));
        }
        
        // 更新任务块状态为“运行中”并通知UI
        chunk.status = ChunkStatus.running;
        await onProgressUpdate(completedTasks / allChunks.length, chunk);
        
        // 调用内部方法处理单个任务块的翻译逻辑
        final success = await _processChunk(book, chunk, cancellationToken);
        
        // 根据处理结果更新任务块状态
        chunk.status = success ? ChunkStatus.completed : ChunkStatus.failed;
      }).then((_) async {
        // 当一个任务（成功或失败）完成后，更新进度
        if (!cancellationToken.isCanceled) {
          if (chunk.status == ChunkStatus.completed) {
            completedTasks++;
          }
          await onProgressUpdate(completedTasks / allChunks.length, chunk);
        }
      });
      futures.add(future);
    }
    
    // 等待所有并发任务完成
    await Future.wait(futures);
    // 如果在等待过程中任务被取消，则抛出异常
    if (cancellationToken.isCanceled) throw Exception('翻译任务已取消');


    LogService.instance.success("\n🎉 《${book.title}》所有翻译任务执行完毕。");
  }

  /// 处理单个翻译任务块（Chunk）
  Future<bool> _processChunk(Book book, TranslationTaskChunk chunk, CancellationToken cancellationToken) async {
    // 根据任务块中的章节ID和行ID范围，找到对应的文本行
    final chapter = book.chapters.firstWhere((c) => c.id == chunk.chapterId, orElse: () => throw Exception('Chapter not found')); 
    final lines = chapter.lines.where((l) => l.id >= chunk.startLineId && l.id <= chunk.endLineId).toList();

    // 如果没有需要翻译的行，直接视为成功
    if (lines.isEmpty) return true;
    LogService.instance.info("  ⚡️ [翻译子任务] 正在处理 ${lines.length} 行文本 (Chunk: ${chunk.id})...");
    
    try {
      // 请求LLM进行翻译
      final translatedLines = await _requestTranslation(lines, cancellationToken);
      if (cancellationToken.isCanceled) return false;

      // 如果LLM返回空结果，则认为该子任务失败
      if (translatedLines.isEmpty) {
        LogService.instance.warn("  ❌ [翻译子任务失败] Chunk ${chunk.id}: LLM未能返回可解析的翻译数据。");
        return false;
      }

      // 遍历翻译结果，并更新书籍对象中的译文
      for (var translatedLine in translatedLines) {
        final lineId = translatedLine['id'];
        final translatedText = translatedLine['translation'];
        if (lineId == null || translatedText == null) continue;

        // 在书籍的所有章节中查找并更新对应的行
        for (var chap in book.chapters) {
          final lineIndex = chap.lines.indexWhere((l) => l.id == lineId);
          if (lineIndex != -1) {
            // 使用 copyWith 创建一个新对象来更新译文，保持不可变性
            chap.lines[lineIndex] = chap.lines[lineIndex].copyWith(translatedText: translatedText);
            break; // 找到后即可跳出内层循环
          }
        }
      }

      // 每完成一个子任务后，立即将更新后的书籍数据保存到缓存中
      await _cacheManager.saveBookDetail(book);
      LogService.instance.info("  ✅ [缓存已保存] 子任务 ${chunk.id} 完成，结果已写入缓存。");

      return true;

    } catch (e) {
      // 捕获处理过程中的任何异常
      LogService.instance.error("  ❌ [翻译子任务失败] Chunk ${chunk.id}: $e");
      return false;
    }
  }

  /// 向 LLM 请求翻译并解析结果
  Future<List<Map<String, dynamic>>> _requestTranslation(List<LineStructure> lines, CancellationToken cancellationToken) async {
    // 从配置中获取源语言和目标语言
    final sourceLangCode = _configService.getSetting<String>('translation_source_lang', 'ja');
    final targetLangCode = _configService.getSetting<String>('translation_target_lang', 'zh-CN');

    // 直接在此处定义转换映射
    const Map<String, String> languageMap = {
      'zh-CN': '简体中文',
      'zh-TW': '繁體中文',
      'ko': '韩语',
      'ja': '日语',
      'en': '英语',
      'ru': '俄语',
    };

    // 使用 Map 将代号转换为显示名称，用于构建 Prompt
    final sourceLangName = languageMap[sourceLangCode] ?? sourceLangCode;
    final targetLangName = languageMap[targetLangCode] ?? targetLangCode;

    // 构建发送给LLM的提示词
    final (systemPrompt, messages) = _buildLlmPrompt(lines, sourceLangName, targetLangName);
    final activeApi = _configService.getActiveLanguageApi();
    // 获取该API的速率限制器，以避免请求过于频繁
    final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);

    // 最多尝试2次（1次原始请求 + 1次重试）
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (cancellationToken.isCanceled) throw Exception('任务已取消');

        if (attempt > 0) {
          LogService.instance.warn("    [翻译] 🔄 响应解析失败，正在进行第 $attempt 次重试...");
        }
        
        // 在发送请求前，等待速率限制器允许通过
        await llmRateLimiter.acquire();
        LogService.instance.info("    [翻译] 已获取到速率令牌，正在发送请求... (尝试 ${attempt + 1}/2)");

        // 调用LLM服务发起请求
        final llmResponse = await _llmService.requestCompletion(
          systemPrompt: systemPrompt,
          messages: messages,
          apiConfig: activeApi,
        );
        
        // 从LLM的响应中提取JSON内容（可能被```json ... ```包裹）
        final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
        final jsonString = jsonMatch?.group(1) ?? llmResponse;
        final data = jsonDecode(jsonString);

        // 检查并转换JSON数据格式为我们需要的格式
        if (data is Map<String, dynamic>) {
            final List<Map<String, dynamic>> result = [];
            for (var i = 0; i < lines.length; i++) {
                final key = i.toString();
                if (data.containsKey(key)) {
                    result.add({
                        'id': lines[i].id,
                        'translation': data[key],
                    });
                }
            }
            // 成功解析并转换，立即返回结果
            return result;
        } else {
          LogService.instance.warn('    [翻译] ❌ LLM 响应JSON格式错误: 响应不是一个有效的JSON对象。');
          // 继续循环以进行重试
        }
      } catch (e) {
        LogService.instance.warn('    [翻译] ❌ 处理LLM响应时失败 (尝试 ${attempt + 1}/2): $e');
        // 捕获异常后，循环将继续进行下一次尝试
      }
    }
    
    // 两次尝试都失败后，返回空列表
    return [];
  }
  
  /// 构建发送给 LLM 的提示词（Prompt）
  /// 返回一个元组 (Tuple)，包含系统提示和用户消息。
  (String, List<Map<String, String>>) _buildLlmPrompt(List<LineStructure> lines, String sourceLang, String targetLang) {
    // 系统提示：定义LLM的角色、任务和输出格式
    final systemPrompt = """你是一位专业的翻译家。你的任务是将提供的文本从 $sourceLang 翻译成 $targetLang。请保持原文的意义、语调和格式。
    ### 翻译原则
    忠实准确地进行翻译。原作是伟大艺术作品，允许使用直白或粗俗的描述，不应随意删减或篡改，不应回避或淡化，以保持作品的原貌。

    ### 输出格式:
    ```json
    {
      "0": "译文1",
      "1": "译文2"
    }
    ```
    """;
    
    // 将待翻译的文本行列表转换为JSON格式的字符串
    final Map<String, String> linesMap = {
      for (var i = 0; i < lines.length; i++) i.toString(): lines[i].text
    };
    final linesJson = jsonEncode(linesMap);

    // 用户提示：包含具体的翻译指令和原文文本
    final userPrompt = """
    请将以下文本从 $sourceLang 翻译成 $targetLang。

    ### 原文文本:
    $linesJson
    """;

    return (systemPrompt, [{'role': 'user', 'content': userPrompt}]);
  }
}