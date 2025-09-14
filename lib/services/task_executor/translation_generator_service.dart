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


class TranslationGeneratorService {
  TranslationGeneratorService._();
  static final TranslationGeneratorService instance = TranslationGeneratorService._();

  final LlmService _llmService = LlmService.instance;
  final ConfigService _configService = ConfigService();
  final CacheManager _cacheManager = CacheManager();

  /// 为指定书籍生成翻译
  Future<void> generateForBook(
    Book book, {
    required CancellationToken cancellationToken,
    required Future<void> Function(double, TranslationTaskChunk) onProgressUpdate,
    required bool Function() isPaused,
  }) async {
    print("🚀 开始为书籍《${book.title}》生成翻译...");

    final bookshelf = await _cacheManager.loadBookshelf();

    final entry = bookshelf.firstWhere((e) => e.id == book.id);
    final allChunks = entry.translationTaskChunks;

    final tasksToRun = allChunks.where((c) => c.status == ChunkStatus.pending || c.status == ChunkStatus.failed).toList();
    print("📖 发现 ${allChunks.length} 个翻译子任务，其中 ${tasksToRun.length} 个需要执行。");
    
    final llmApi = _configService.getActiveLanguageApi();
    final llmConcurrency = llmApi.concurrencyLimit ?? 1;
    final llmPool = Pool(llmConcurrency);
    print("🛠️ 启动翻译任务池，最大并发数: $llmConcurrency (来自语言API '${llmApi.name}')");

    int completedTasks = allChunks.length - tasksToRun.length;
    final List<Future> futures = [];

    for (final chunk in tasksToRun) {
      final future = llmPool.withResource(() async {
        if (cancellationToken.isCanceled) return;

        // 检查暂停状态
        while (isPaused()) {
          if (cancellationToken.isCanceled) return;
          await Future.delayed(const Duration(seconds: 1));
        }
        
        chunk.status = ChunkStatus.running;
        await onProgressUpdate(completedTasks / allChunks.length, chunk);
        
        final success = await _processChunk(book, chunk, cancellationToken);
        
        chunk.status = success ? ChunkStatus.completed : ChunkStatus.failed;
      }).then((_) async {
        if (!cancellationToken.isCanceled) {
          if (chunk.status == ChunkStatus.completed) {
            completedTasks++;
          }
          await onProgressUpdate(completedTasks / allChunks.length, chunk);
        }
      });
      futures.add(future);
    }
    
    await Future.wait(futures);
    if (cancellationToken.isCanceled) throw Exception('翻译任务已取消');


    print("\n🎉 《${book.title}》所有翻译任务执行完毕。");
  }

  /// 处理单个翻译任务块
  Future<bool> _processChunk(Book book, TranslationTaskChunk chunk, CancellationToken cancellationToken) async {
    final chapter = book.chapters.firstWhere((c) => c.title == chunk.chapterTitle, orElse: () => throw Exception('Chapter not found'));
    final lines = chapter.lines.where((l) => l.id >= chunk.startLineId && l.id <= chunk.endLineId).toList();

    if (lines.isEmpty) return true;
    print("  ⚡️ [翻译子任务] 正在处理 ${lines.length} 行文本...");
    
    try {
      final translatedLines = await _requestTranslation(lines, cancellationToken);
      if (cancellationToken.isCanceled) return false;

      // [修改] 增加对空结果的判断
      if (translatedLines.isEmpty) {
        print("  ❌ [翻译子任务失败]: LLM未能返回可解析的翻译数据。");
        return false;
      }

      for (var translatedLine in translatedLines) {
        final lineId = translatedLine['id'];
        final translatedText = translatedLine['translation'];
        if (lineId == null || translatedText == null) continue;

        for (var chap in book.chapters) {
          final lineIndex = chap.lines.indexWhere((l) => l.id == lineId);
          if (lineIndex != -1) {
            chap.lines[lineIndex] = chap.lines[lineIndex].copyWith(translatedText: translatedText);
            break; 
          }
        }
      }

      // 完成一个子任务后立即保存缓存 ---
      await _cacheManager.saveBookDetail(book);
      print("  ✅ [缓存已保存] 子任务 ${chunk.id} 完成，结果已写入缓存。");

      return true;

    } catch (e) {
      print("  ❌ [翻译子任务失败]: $e");
      return false;
    }
  }

  /// 向 LLM 请求翻译并解析结果
  Future<List<Map<String, dynamic>>> _requestTranslation(List<LineStructure> lines, CancellationToken cancellationToken) async {
    final sourceLang = _configService.getSetting<String>('translation_source_lang', '日语');
    final targetLang = _configService.getSetting<String>('translation_target_lang', '中文');
    final (systemPrompt, messages) = _buildLlmPrompt(lines, sourceLang, targetLang);
    final activeApi = _configService.getActiveLanguageApi();
    final llmRateLimiter = _configService.getRateLimiterForApi(activeApi);

    // 最多尝试2次（1次原始 + 1次重试）
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (cancellationToken.isCanceled) throw Exception('任务已取消');

        if (attempt > 0) {
          print("    [翻译] 🔄 响应解析失败，正在进行第 $attempt 次重试...");
        }
        
        // 每次尝试前都获取速率令牌
        await llmRateLimiter.acquire();
        print("    [翻译] 已获取到速率令牌，正在发送请求... (尝试 ${attempt + 1}/2)");

        final llmResponse = await _llmService.requestCompletion(
          systemPrompt: systemPrompt,
          messages: messages,
          apiConfig: activeApi,
        );
        
        final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(llmResponse);
        final jsonString = jsonMatch?.group(1) ?? llmResponse;
        final data = jsonDecode(jsonString);

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
            // 成功解析并转换，立即返回
            return result;
        } else {
          print('    [翻译] ❌ LLM 响应JSON格式错误: 响应不是一个有效的JSON对象。');
          // 继续循环以重试
        }
      } catch (e) {
        print('    [翻译] ❌ 处理LLM响应时失败 (尝试 ${attempt + 1}/2): $e');
        // 捕获异常后，循环将继续进行下一次尝试
      }
    }
    
    // 两次尝试都失败后，返回空列表
    return [];
  }
  
  /// 构建发送给 LLM 的提示词
  (String, List<Map<String, String>>) _buildLlmPrompt(List<LineStructure> lines, String sourceLang, String targetLang) {
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
    
    final Map<String, String> linesMap = {
      for (var i = 0; i < lines.length; i++) i.toString(): lines[i].text
    };
    final linesJson = jsonEncode(linesMap);

    final userPrompt = """
    请将以下文本从 $sourceLang 翻译成 $targetLang。

    ### 原文文本:
    $linesJson
    """;

    return (systemPrompt, [{'role': 'user', 'content': userPrompt}]);
  }
}