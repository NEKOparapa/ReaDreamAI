// lib/services/task_splitter/task_splitter_service.dart

import 'dart:math';
import 'package:tiktoken/tiktoken.dart';
import 'package:uuid/uuid.dart';

import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';

/// 任务切分器服务
/// 负责将书籍内容根据不同任务类型（如插图、翻译）切分成小的、可执行的任务块（Chunk）。
class TaskSplitterService {
  // 使用私有构造函数实现单例模式
  TaskSplitterService._();

  // 提供全局唯一的服务实例
  static final TaskSplitterService instance = TaskSplitterService._();

  // 依赖的服务
  final ConfigService _configService = ConfigService();
  final _uuid = const Uuid();

  /// 将书籍内容拆分为适合生成插图的任务块
  List<IllustrationTaskChunk> splitBookForIllustrations(Book book) {
    final scenesPerChapter = _configService.getSetting<int>('image_gen_scenes_per_chapter', 3);
    final maxChunkTokens = _configService.getSetting<int>('image_gen_tokens', 5000);
    final List<IllustrationTaskChunk> allChunks = [];
    final encoding = encodingForModel("gpt-4");

    for (final chapter in book.chapters) {
      if (chapter.lines.isEmpty) continue;

      int totalChapterChars = chapter.lines.map((line) => line.text.length).reduce((a, b) => a + b);

      if (totalChapterChars < 500) {
        LogService.instance.info('跳过插图任务章节《${chapter.title}》，因字符数 ($totalChapterChars) 过少。');
        continue;
      }

      final List<List<LineStructure>> lineChunks = [];
      List<LineStructure> currentChunkLines = [];
      int currentTokens = 0;

      for (final line in chapter.lines) {
        final lineTokens = encoding.encode(line.text).length;
        if (currentTokens + lineTokens > maxChunkTokens && currentChunkLines.isNotEmpty) {
          lineChunks.add(List.from(currentChunkLines));
          currentChunkLines.clear();
          currentTokens = 0;
        }
        currentChunkLines.add(line);
        currentTokens += lineTokens;
      }

      if (currentChunkLines.isNotEmpty) {
        lineChunks.add(List.from(currentChunkLines));
      }

      if (lineChunks.isEmpty) continue;

      final chunkTokens = lineChunks
          .map((chunk) => encoding.encode(chunk.map((l) => l.text).join('\n')).length)
          .toList();
      final totalChunkTokens = chunkTokens.fold<int>(0, (sum, item) => sum + item);

      final List<int> scenesPerChunk = [];
      if (totalChunkTokens > 0) {
        int distributedScenes = 0;
        for (int i = 0; i < chunkTokens.length - 1; i++) {
          final numScenes = (chunkTokens[i] / totalChunkTokens * scenesPerChapter).round();
          scenesPerChunk.add(numScenes);
          distributedScenes += numScenes;
        }
        scenesPerChunk.add(max(0, scenesPerChapter - distributedScenes));
      } else if (lineChunks.isNotEmpty) {
        scenesPerChunk.addAll(List.filled(lineChunks.length, 0));
        scenesPerChunk[0] = scenesPerChapter;
      }

      for (int i = 0; i < lineChunks.length; i++) {
        if (scenesPerChunk[i] > 0) {
          final chunkLines = lineChunks[i];
          allChunks.add(IllustrationTaskChunk(
            id: _uuid.v4(),
            chapterId: chapter.id,
            startLineId: chunkLines.first.id,
            endLineId: chunkLines.last.id,
            scenesToGenerate: scenesPerChunk[i],
          ));
        }
      }
    }

    return allChunks;
  }

  /// 将书籍内容拆分为适合翻译的任务块
  List<TranslationTaskChunk> splitBookForTranslations(Book book) {
    final maxChunkTokens = _configService.getSetting<int>('translation_tokens', 4000);
    final List<TranslationTaskChunk> allChunks = [];
    final encoding = encodingForModel("gpt-4");

    for (final chapter in book.chapters) {
      if (chapter.lines.isEmpty) continue;

      int totalChapterChars = chapter.lines.map((line) => line.text.length).reduce((a, b) => a + b);

      if (totalChapterChars < 500) {
        LogService.instance.info('跳过翻译任务章节《${chapter.title}》，因字符数 ($totalChapterChars) 过少。');
        continue;
      }

      List<LineStructure> currentChunkLines = [];
      int currentTokens = 0;

      for (final line in chapter.lines) {
        final lineTokens = encoding.encode(line.text).length;
        if (currentTokens + lineTokens > maxChunkTokens && currentChunkLines.isNotEmpty) {
          allChunks.add(TranslationTaskChunk(
            id: _uuid.v4(),
            chapterId: chapter.id,
            startLineId: currentChunkLines.first.id,
            endLineId: currentChunkLines.last.id,
          ));
          currentChunkLines.clear();
          currentTokens = 0;
        }
        currentChunkLines.add(line);
        currentTokens += lineTokens;
      }

      if (currentChunkLines.isNotEmpty) {
        allChunks.add(TranslationTaskChunk(
          id: _uuid.v4(),
          chapterId: chapter.id,
          startLineId: currentChunkLines.first.id,
          endLineId: currentChunkLines.last.id,
        ));
      }
    }

    return allChunks;
  }
}