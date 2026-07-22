// lib/ui/creation/ai_novel_creation/novel_generation_progress_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../base/api_model.dart';
import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/book.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../models/character_card_model.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/task_executor/novel_generator_service.dart';

// 定义章节状态
enum ChapterStatus { pending, planning, generating, completed, error }

// 定义章节生成信息的模型
class ChapterGenerationInfo {
  ChapterStatus status;
  String? content;
  int charCount;
  double progress; // 用于追踪单章节进度

  ChapterGenerationInfo({
    this.status = ChapterStatus.pending,
    this.content,
    this.charCount = 0,
    this.progress = 0.0, // 默认值为0
  });
}

// 定义日志模型
class GenerationLog {
  final DateTime timestamp;
  final String message;
  final IconData icon;

  GenerationLog(this.message, this.icon) : timestamp = DateTime.now();
}

class NovelGenerationProgressPage extends StatefulWidget {
  final Map<String, dynamic> outline;
  final bool isLinearMode;

  const NovelGenerationProgressPage({
    super.key,
    required this.outline,
    this.isLinearMode = false,
  });

  @override
  State<NovelGenerationProgressPage> createState() =>
      _NovelGenerationProgressPageState();
}

class _NovelGenerationProgressPageState
    extends State<NovelGenerationProgressPage> {
  final _configService = ConfigService();
  double _progress = 0.0;
  String _mainStatus = '准备就绪...';
  String _detailedStatus = '即将开始生成流程';
  final List<GenerationLog> _logs = [];
  bool _isFinished = false;
  bool _hasError = false;
  bool _isTerminated = false;
  bool _isSaving = false;

  late List<ChapterGenerationInfo> _chapterInfos;
  // 主滚动控制器
  final ScrollController _scrollController = ScrollController();
  // 日志专用滚动控制器
  final ScrollController _logScrollController = ScrollController();

  bool _isSavableChapter(ChapterGenerationInfo info) {
    return info.content != null && info.content!.trim().isNotEmpty;
  }

  int get _savableChapterCount => _chapterInfos.where(_isSavableChapter).length;

  bool get _hasSavableChapterContent => _savableChapterCount > 0;

  bool get _allChaptersCompleted =>
      _chapterInfos.every((info) => info.status == ChapterStatus.completed);

  void _updateFinishedStatusText({bool globalError = false}) {
    final savableCount = _savableChapterCount;

    if (_isTerminated) {
      _mainStatus = '任务已终止';
      _detailedStatus = savableCount > 0
          ? '可保存已生成的 $savableCount 个章节'
          : '生成过程已停止，尚无可保存章节';
      return;
    }

    if (_hasError) {
      _mainStatus = globalError && savableCount == 0 ? '生成失败' : '部分章节生成失败';
      _detailedStatus = savableCount > 0
          ? '可保存已生成章节，也可以重试失败章节'
          : '您可以尝试重新生成失败的章节';
      return;
    }

    if (_allChaptersCompleted && savableCount == _chapterInfos.length) {
      _mainStatus = '所有章节已生成！';
      _detailedStatus = '请检查内容，然后点击“完成并保存”';
      return;
    }

    _mainStatus = savableCount > 0 ? '部分章节已生成' : '尚无可保存章节';
    _detailedStatus = savableCount > 0 ? '可保存已生成章节，也可以继续补全' : '请继续生成或重试失败章节';
  }

  @override
  void initState() {
    super.initState();
    _chapterInfos = List.generate(
      widget.outline['storyline'].length,
      (_) => ChapterGenerationInfo(),
    );
    Future.microtask(() => startGeneration());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String message, IconData icon) {
    if (mounted) {
      setState(() {
        _logs.add(GenerationLog(message, icon));
      });
      // 自动滚动日志视图到底部
      Timer(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 开始生成流程
  Future<void> startGeneration() async {
    if (widget.isLinearMode) {
      await _startLinearGeneration();
    } else {
      await _startParallelGeneration();
    }
  }

  /// Returns the configured API for novel body generation.
  ApiModel _getNovelGenerateApi() {
    return _configService.getLanguageApiById(
      _configService.getSetting<String?>(
        'ai_novel_creation_generate_api_id',
        null,
      ),
    );
  }

  /// Parallel generation mode: plan and write chapters concurrently.
  Future<void> _startParallelGeneration() async {
    LogService.instance.info('开始并行生成小说正文...');
    _addLog('生成任务已启动（完全并行模式）', Icons.flash_on);
    setState(() {
      _mainStatus = '正在并行生成所有章节...';
      _detailedStatus = '任务已分发';
    });

    final wordsPerChapter = _configService.getSetting<int>(
      'ai_novel_creation_words_per_chapter',
      1500,
    );
    _addLog('目标字数设定为每章约 $wordsPerChapter 字', Icons.format_size);

    final llmApi = _getNovelGenerateApi();
    final concurrency = max(1, llmApi.concurrencyLimit ?? 3);
    final pool = Pool(concurrency);
    LogService.instance.info(
      'Novel body generation pool started. API: ${llmApi.name}, max concurrency: $concurrency',
    );

    try {
      final storyline = List<Map<String, dynamic>>.from(
        widget.outline['storyline'],
      );
      final characters = List<Map<String, dynamic>>.from(
        widget.outline['main_characters'],
      );
      final futures = <Future>[];
      int completedChapters = 0;

      for (int i = 0; i < storyline.length; i++) {
        futures.add(
          pool.withResource(() async {
            if (_isTerminated || !mounted) return;

            setState(() {
              _chapterInfos[i].status = ChapterStatus.generating;
            });
            // 并行模式下，规划和写作是一起进行的，无法共享上下文
            _addLog(
              '开始生成第 ${i + 1} 章: "${storyline[i]['chapter_title']}"...',
              Icons.cloud_upload_outlined,
            );

            try {
              final content = await NovelGeneratorService.instance
                  .generateChapterContent(
                    title: widget.outline['title'],
                    backgroundSetting: widget.outline['background_setting'],
                    writingStyle: widget.outline['writing_style'],
                    mainCharacters: characters,
                    storyline: storyline,
                    chapterIndex: i,
                    wordsPerChapter: wordsPerChapter,
                    onProgress: (message, chapterProgress) {
                      if (mounted && !_isTerminated) {
                        setState(() {
                          _detailedStatus = '第 ${i + 1} 章: $message';
                          _chapterInfos[i].progress = chapterProgress;
                        });
                      }
                    },
                    isTerminated: () => _isTerminated,
                  );

              if (_isTerminated || !mounted) return;

              if (content.isEmpty) {
                throw Exception("内容生成被跳过或终止");
              }

              _chapterInfos[i].content = content;
              _chapterInfos[i].charCount = content.length;
              _addLog('第 ${i + 1} 章内容已成功接收', Icons.cloud_download_outlined);

              if (mounted) {
                setState(() {
                  completedChapters++;
                  _chapterInfos[i].status = ChapterStatus.completed;
                  _chapterInfos[i].progress = 1.0;
                  _progress = completedChapters / storyline.length;
                  _mainStatus = '正在创作 ($completedChapters/${storyline.length})';
                  _detailedStatus = '“${storyline[i]['chapter_title']}” 已完成';
                });
              }
            } catch (e, s) {
              if (_isTerminated || !mounted) return;
              Object error = e;
              if (e is Map &&
                  e.containsKey('error') &&
                  e.containsKey('partialContent')) {
                final partialContent = e['partialContent'] as String;
                error = e['error'] ?? e;
                if (mounted) {
                  _chapterInfos[i].content = partialContent;
                  _chapterInfos[i].charCount = partialContent.length;
                }
              }
              LogService.instance.error('生成第 ${i + 1} 章时失败', error, s);
              _addLog('第 ${i + 1} 章生成失败: $error', Icons.error_outline);
              if (mounted) {
                setState(() {
                  _chapterInfos[i].status = ChapterStatus.error;
                  _hasError = true;
                });
              }
            }
          }),
        );
      }

      await Future.wait(futures);

      if (_isTerminated) {
        _handleTermination();
        return;
      }

      if (!mounted) return;

      setState(() {
        _isFinished = true;
        _updateFinishedStatusText();
      });
    } catch (e, s) {
      _handleGlobalError(e, s);
    }
  }

  /// 线性生成模式：串行规划 -> 并行写作
  Future<void> _startLinearGeneration() async {
    LogService.instance.info('开始线性生成模式（串行规划 -> 并行写作）...');
    _addLog('生成任务已启动（线性规划模式）', Icons.account_tree_outlined);

    final wordsPerChapter = _configService.getSetting<int>(
      'ai_novel_creation_words_per_chapter',
      1500,
    );
    _addLog('目标字数设定为每章约 $wordsPerChapter 字', Icons.format_size);

    final storyline = List<Map<String, dynamic>>.from(
      widget.outline['storyline'],
    );
    final characters = List<Map<String, dynamic>>.from(
      widget.outline['main_characters'],
    );

    // =========================================================
    // 阶段一：串行规划 (Sequential Planning Phase)
    // =========================================================

    // 用于收集所有章节的规划，作为上下文传递给下一章
    final List<Map<String, dynamic>> cumulativePlans = [];

    try {
      for (int i = 0; i < storyline.length; i++) {
        if (_isTerminated || !mounted) return;

        setState(() {
          _mainStatus = '正在构建大纲结构 (${i + 1}/${storyline.length})';
          _detailedStatus = '正在规划第 ${i + 1} 章剧情走向...';
          _chapterInfos[i].status =
              ChapterStatus.planning; // 使用新状态或复用generating
          _chapterInfos[i].progress = 0.05; // 视觉上给一点进度
        });

        // 滚动到当前章节
        if (_scrollController.hasClients) {
          final itemHeight = 72.0; // 假设列表项高度
          final offset = min(
            i * itemHeight,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }

        // 调用 Service 生成规划并缓存
        final List<String> plan = await NovelGeneratorService.instance
            .generateAndCacheChapterPlan(
              title: widget.outline['title'],
              backgroundSetting: widget.outline['background_setting'],
              writingStyle: widget.outline['writing_style'],
              mainCharacters: characters,
              storyline: storyline,
              chapterIndex: i,
              wordsPerChapter: wordsPerChapter,
              isTerminated: () => _isTerminated,
              previousChapterPlans: cumulativePlans, // 关键：将之前所有章节的规划传进去
            );

        // 将生成的规划加入上下文列表
        cumulativePlans.add({
          'chapterIndex': i,
          'chapterTitle': storyline[i]['chapter_title'],
          'plans': plan,
        });

        _addLog('第 ${i + 1} 章剧情结构规划完成', Icons.assignment_turned_in_outlined);
      }
    } catch (e, s) {
      LogService.instance.error('规划阶段发生错误', e, s);
      _addLog('剧情规划中断: $e', Icons.error_outline);
      if (mounted) {
        setState(() {
          _mainStatus = '规划失败';
          _detailedStatus = '请检查网络或配置';
          _hasError = true;
          _isFinished = true;
        });
      }
      return;
    }

    if (_isTerminated) {
      _handleTermination();
      return;
    }

    // =========================================================
    // 阶段二：并行写作 (Parallel Writing Phase)
    // =========================================================

    LogService.instance.info('全局规划完成，开始并行生成正文...');
    _addLog('全局规划完成，开始并行生成正文内容...', Icons.flash_on);

    if (mounted) {
      setState(() {
        _mainStatus = '正在并行生成正文...';
        _detailedStatus = '全速写作中';
      });
    }

    final llmApi = _getNovelGenerateApi();
    final concurrency = max(1, llmApi.concurrencyLimit ?? 3);
    final pool = Pool(concurrency);
    LogService.instance.info(
      'Parallel chapter writing uses API: ${llmApi.name}, max concurrency: $concurrency',
    );
    final futures = <Future>[];
    int completedChapters = 0;

    for (int i = 0; i < storyline.length; i++) {
      futures.add(
        pool.withResource(() async {
          if (_isTerminated || !mounted) return;

          setState(() {
            _chapterInfos[i].status = ChapterStatus.generating;
          });

          try {
            // 调用 generateChapterContent。
            // 因为 Service 中已经有了 _segmentPlanCache，它会跳过规划步骤，直接开始写正文。
            final content = await NovelGeneratorService.instance
                .generateChapterContent(
                  title: widget.outline['title'],
                  backgroundSetting: widget.outline['background_setting'],
                  writingStyle: widget.outline['writing_style'],
                  mainCharacters: characters,
                  storyline: storyline,
                  chapterIndex: i,
                  wordsPerChapter: wordsPerChapter,
                  // 传入上下文（虽然规划已缓存，但保持一致性）
                  previousChapterPlans: cumulativePlans,
                  onProgress: (message, chapterProgress) {
                    if (mounted && !_isTerminated) {
                      setState(() {
                        _detailedStatus = '第 ${i + 1} 章: $message';
                        _chapterInfos[i].progress = chapterProgress;
                      });
                    }
                  },
                  isTerminated: () => _isTerminated,
                );

            if (_isTerminated || !mounted) return;
            if (content.isEmpty) throw Exception("内容生成为空");

            _chapterInfos[i].content = content;
            _chapterInfos[i].charCount = content.length;
            _addLog('第 ${i + 1} 章正文完成', Icons.check_circle_outline);

            if (mounted) {
              setState(() {
                completedChapters++;
                _chapterInfos[i].status = ChapterStatus.completed;
                _chapterInfos[i].progress = 1.0;
                _progress = completedChapters / storyline.length;
                _mainStatus = '正在创作 ($completedChapters/${storyline.length})';
              });
            }
          } catch (e, s) {
            if (_isTerminated) return;

            Object error = e;
            if (e is Map &&
                e.containsKey('error') &&
                e.containsKey('partialContent')) {
              final partialContent = e['partialContent'] as String;
              error = e['error'] ?? e;
              if (mounted) {
                _chapterInfos[i].content = partialContent;
                _chapterInfos[i].charCount = partialContent.length;
              }
            }

            LogService.instance.error('生成第 ${i + 1} 章内容失败', error, s);
            _addLog('第 ${i + 1} 章生成失败: $error', Icons.error_outline);
            if (mounted) {
              setState(() {
                _chapterInfos[i].status = ChapterStatus.error;
                _hasError = true;
              });
            }
          }
        }),
      );
    }

    await Future.wait(futures);

    if (_isTerminated) {
      _handleTermination();
      return;
    }

    if (mounted) {
      setState(() {
        _isFinished = true;
        _updateFinishedStatusText();
      });
    }
  }

  void _handleTermination() {
    _addLog('任务已被用户手动终止', Icons.cancel_outlined);
    setState(() {
      _isFinished = true;
      _updateFinishedStatusText();
    });
  }

  void _handleGlobalError(Object e, StackTrace s) {
    LogService.instance.error('小说生成过程中发生错误', e, s);
    if (!_hasError) _addLog('发生严重错误: $e', Icons.error_outline);
    if (mounted) {
      setState(() {
        _hasError = true;
        _isFinished = true;
        _updateFinishedStatusText(globalError: true);
      });
    }
  }

  /// 重新生成指定章节
  Future<void> _regenerateChapter(int index) async {
    if (_isTerminated || _isSaving) return;

    // 清除该章节的规划缓存，以确保生成全新的计划
    NovelGeneratorService.instance.clearChapterPlanCache(
      widget.outline['title'],
      index,
    );

    final storyline = List<Map<String, dynamic>>.from(
      widget.outline['storyline'],
    );
    _addLog('开始重新生成第 ${index + 1} 章...', Icons.refresh);
    setState(() {
      _isFinished = false;
      _mainStatus = '正在重新生成...';
      _detailedStatus =
          '处理第 ${index + 1} 章: "${storyline[index]['chapter_title']}"';
      _chapterInfos[index].status = ChapterStatus.generating;
      _chapterInfos[index].content = null;
      _chapterInfos[index].charCount = 0;
      _chapterInfos[index].progress = 0.0;
      _hasError = _chapterInfos.any(
        (info) => info.status == ChapterStatus.error,
      );
    });

    final characters = List<Map<String, dynamic>>.from(
      widget.outline['main_characters'],
    );
    final wordsPerChapter = _configService.getSetting<int>(
      'ai_novel_creation_words_per_chapter',
      1500,
    );

    try {
      final content = await NovelGeneratorService.instance
          .generateChapterContent(
            title: widget.outline['title'],
            backgroundSetting: widget.outline['background_setting'],
            writingStyle: widget.outline['writing_style'],
            mainCharacters: characters,
            storyline: storyline,
            chapterIndex: index,
            wordsPerChapter: wordsPerChapter,
            onProgress: (message, chapterProgress) {
              if (mounted && !_isTerminated) {
                setState(() {
                  _detailedStatus = '第 ${index + 1} 章: $message';
                  _chapterInfos[index].progress = chapterProgress;
                });
              }
            },
            isTerminated: () => _isTerminated,
          );

      if (_isTerminated || !mounted) return;
      if (content.isEmpty) throw Exception("内容生成被跳过或为空");

      _addLog('第 ${index + 1} 章已成功重新生成', Icons.check_circle_outline);
      if (mounted) {
        setState(() {
          _chapterInfos[index].content = content;
          _chapterInfos[index].charCount = content.length;
          _chapterInfos[index].status = ChapterStatus.completed;
          _chapterInfos[index].progress = 1.0;
        });
      }
    } catch (e, s) {
      if (_isTerminated || !mounted) return;
      Object error = e;
      if (e is Map &&
          e.containsKey('error') &&
          e.containsKey('partialContent')) {
        final partialContent = e['partialContent'] as String;
        error = e['error'] ?? e;
        if (mounted) {
          _chapterInfos[index].content = partialContent;
          _chapterInfos[index].charCount = partialContent.length;
        }
      }
      LogService.instance.error('重新生成第 ${index + 1} 章时失败', error, s);
      _addLog('第 ${index + 1} 章重新生成失败: $error', Icons.error_outline);
      if (mounted) {
        setState(() {
          _chapterInfos[index].status = ChapterStatus.error;
          _hasError = true;
        });
      }
    } finally {
      if (mounted) {
        final isStillGenerating = _chapterInfos.any(
          (info) =>
              info.status == ChapterStatus.generating ||
              info.status == ChapterStatus.planning,
        );
        if (!isStillGenerating) {
          _isFinished = true;
          _hasError = _chapterInfos.any(
            (info) => info.status == ChapterStatus.error,
          );
          _updateFinishedStatusText();
          final completedCount = _chapterInfos
              .where((c) => c.status == ChapterStatus.completed)
              .length;
          _progress = completedCount / _chapterInfos.length;
          setState(() {});
        }
      }
    }
  }

  /// 从断点继续生成指定章节
  Future<void> _continueChapter(int index) async {
    if (_isTerminated || _isSaving) return;

    final storyline = List<Map<String, dynamic>>.from(
      widget.outline['storyline'],
    );
    _addLog('尝试从断点继续生成第 ${index + 1} 章...', Icons.play_circle_outline);
    setState(() {
      _isFinished = false;
      _mainStatus = '正在继续生成...';
      _detailedStatus =
          '处理第 ${index + 1} 章: "${storyline[index]['chapter_title']}"';
      _chapterInfos[index].status = ChapterStatus.generating;
      _hasError = _chapterInfos.any(
        (info) =>
            info.status == ChapterStatus.error && info != _chapterInfos[index],
      );
    });

    final characters = List<Map<String, dynamic>>.from(
      widget.outline['main_characters'],
    );
    final wordsPerChapter = _configService.getSetting<int>(
      'ai_novel_creation_words_per_chapter',
      1500,
    );

    final String initialContent = _chapterInfos[index].content ?? '';
    final double initialProgress = _chapterInfos[index].progress;
    final segmentCount = max(1, (wordsPerChapter / 1500).ceil());
    final startSegmentIndex = (initialProgress * segmentCount).floor();

    _addLog(
      '将从第 ${startSegmentIndex + 1} / $segmentCount 段开始',
      Icons.skip_next_outlined,
    );

    final contentForResume = initialContent.trim().isEmpty
        ? ''
        : '$initialContent\n\n';

    try {
      final newContent = await NovelGeneratorService.instance
          .generateChapterContent(
            title: widget.outline['title'],
            backgroundSetting: widget.outline['background_setting'],
            writingStyle: widget.outline['writing_style'],
            mainCharacters: characters,
            storyline: storyline,
            chapterIndex: index,
            wordsPerChapter: wordsPerChapter,
            initialContent: contentForResume,
            startSegmentIndex: startSegmentIndex,
            onProgress: (message, chapterProgress) {
              if (mounted && !_isTerminated) {
                setState(() {
                  _detailedStatus = '第 ${index + 1} 章: $message';
                  _chapterInfos[index].progress = chapterProgress;
                });
              }
            },
            isTerminated: () => _isTerminated,
          );

      if (_isTerminated || !mounted) return;
      if (newContent.isEmpty) throw Exception("内容生成被跳过或为空");

      _addLog('第 ${index + 1} 章已成功续写完成', Icons.check_circle_outline);
      if (mounted) {
        setState(() {
          _chapterInfos[index].content = newContent;
          _chapterInfos[index].charCount = newContent.length;
          _chapterInfos[index].status = ChapterStatus.completed;
          _chapterInfos[index].progress = 1.0;
        });
      }
    } catch (e, s) {
      if (_isTerminated || !mounted) return;
      Object error = e;
      if (e is Map &&
          e.containsKey('error') &&
          e.containsKey('partialContent')) {
        final partialContent = e['partialContent'] as String;
        error = e['error'] ?? e;
        if (mounted) {
          _chapterInfos[index].content = partialContent;
          _chapterInfos[index].charCount = partialContent.length;
        }
      }
      LogService.instance.error('续写第 ${index + 1} 章时失败', error, s);
      _addLog('第 ${index + 1} 章续写失败: $error', Icons.error_outline);
      if (mounted) {
        setState(() {
          _chapterInfos[index].status = ChapterStatus.error;
          _hasError = true;
        });
      }
    } finally {
      if (mounted) {
        final isStillGenerating = _chapterInfos.any(
          (info) => info.status == ChapterStatus.generating,
        );
        if (!isStillGenerating) {
          _isFinished = true;
          _hasError = _chapterInfos.any(
            (info) => info.status == ChapterStatus.error,
          );
          _updateFinishedStatusText();
          final completedCount = _chapterInfos
              .where((c) => c.status == ChapterStatus.completed)
              .length;
          _progress = completedCount / _chapterInfos.length;
          setState(() {});
        }
      }
    }
  }

  /// 最终保存书籍
  Future<void> _saveGeneratedBook() async {
    final savableChapterCount = _savableChapterCount;
    if (savableChapterCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('尚无可保存的章节正文。')));
      return;
    }

    setState(() {
      _isSaving = true;
      _mainStatus = '正在保存书籍';
      _detailedStatus = '编译章节内容...';
    });
    _addLog('正在整理 $savableChapterCount 个已生成章节成书...', Icons.menu_book_outlined);

    try {
      final storyline = List<Map<String, dynamic>>.from(
        widget.outline['storyline'],
      );
      final List<ChapterStructure> finalChapters = [];
      final fullTextBuilder = StringBuffer();
      int globalLineIdCounter = 0;

      for (int i = 0; i < storyline.length; i++) {
        final content = _chapterInfos[i].content?.trim();
        if (content == null || content.isEmpty) {
          continue;
        }
        fullTextBuilder.write(
          "## ${storyline[i]['chapter_title']}\n\n$content\n\n---\n\n",
        );

        final chapterLines = _createLines(
          content,
          'content.txt',
          globalLineIdCounter,
        );
        final newChapter = ChapterStructure(
          id: const Uuid().v4(),
          title: storyline[i]['chapter_title'],
          sourceFile: 'content.txt',
          lines: chapterLines,
          chapterSummary: storyline[i]['chapter_summary'],
          timeSpan: storyline[i]['time_span'],
          settingUpdate: storyline[i]['setting_update'],
        );
        finalChapters.add(newChapter);
        globalLineIdCounter += chapterLines.length;
      }

      await _saveBook(finalChapters, fullTextBuilder.toString());

      _addLog(
        '《${widget.outline['title']}》已成功保存到书架！',
        Icons.check_circle_outline,
      );
      if (mounted) {
        setState(() {
          _mainStatus = '保存成功！';
          _detailedStatus = '您的新书已在书架上等您';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e, s) {
      LogService.instance.error('保存书籍时发生错误', e, s);
      _addLog('保存失败: $e', Icons.error_outline);
      if (mounted) {
        setState(() {
          _mainStatus = '保存失败';
          _detailedStatus = '请检查日志后重试';
          _hasError = true;
          _isSaving = false;
        });
      }
    }
  }

  List<LineStructure> _createLines(
    String content,
    String sourceFilename,
    int startLineId,
  ) {
    final List<LineStructure> result = [];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    int lineId = startLineId;
    for (final lineText in lines) {
      if (lineText.trim().isNotEmpty) {
        result.add(
          LineStructure(
            id: lineId++,
            text: lineText.trim(),
            sourceInfo: sourceFilename,
            originalContent: lineText,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _saveBook(
    List<ChapterStructure> chapters,
    String fullTextContent,
  ) async {
    if (!mounted) return;
    final title = widget.outline['title'];
    LogService.instance.info('开始保存书籍: 《$title》');
    _addLog('创建临时文件...', Icons.file_present_outlined);
    setState(() => _detailedStatus = '正在写入临时文件...');

    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
    final tempFileName = '$sanitizedTitle.txt';
    final tempFilePath = p.join(tempDir.path, tempFileName);
    final tempFile = File(tempFilePath);
    await tempFile.writeAsString(fullTextContent);

    if (!mounted) return;
    _addLog('创建书籍缓存结构...', Icons.folder_zip_outlined);
    setState(() => _detailedStatus = '正在初始化书籍缓存...');

    final cacheManager = CacheManager();
    final (String bookId, String cachedPath, _) = await cacheManager
        .createBookCacheInfrastructure(tempFilePath);
    LogService.instance.info('书籍缓存基础设施已创建，ID: $bookId, 路径: $cachedPath');
    await tempFile.delete();

    if (!mounted) return;
    _addLog('正在保存书籍元数据...', Icons.dns_outlined);
    setState(() => _detailedStatus = '正在保存书籍详细信息...');

    final characters = (widget.outline['main_characters'] as List)
        .map((c) => CharacterCard.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    final newBook = Book(
      id: bookId,
      title: title,
      fileType: 'txt',
      originalPath: 'none',
      cachedPath: cachedPath,
      chapters: chapters,
      introduction: widget.outline['introduction'],
      backgroundSetting: widget.outline['background_setting'],
      writingStyle: widget.outline['writing_style'],
      characters: characters,
      coverImagePath: null,
    );

    final subCachePath = await cacheManager.saveBookDetail(newBook);

    if (!mounted) return;
    _addLog('正在将书籍添加到书架...', Icons.library_add_outlined);
    setState(() => _detailedStatus = '正在更新书架...');

    final newEntry = BookshelfEntry(
      id: bookId,
      title: newBook.title,
      originalPath: 'none',
      fileType: 'txt',
      subCachePath: subCachePath,
      coverImagePath: null,
    );

    final entries = await cacheManager.loadBookshelf();
    entries.add(newEntry);
    await cacheManager.saveBookshelf(entries);
    LogService.instance.success('书籍保存流程完成。');
  }

  void _terminateTask() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认终止任务'),
        content: const Text('您确定要停止生成小说吗？当前进度将不会被保存。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认终止'),
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isTerminated = true);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressColor = _hasError ? colorScheme.error : colorScheme.primary;

    return WillPopScope(
      onWillPop: () async => _isFinished || _isTerminated,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isFinished ? '生成完成' : '正在生成小说...'),
          automaticallyImplyLeading: _isFinished || _isTerminated,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildProgressIndicator(progressColor, theme),
                    const SizedBox(width: 16),
                    Expanded(child: _buildMonitoringCards(theme)),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                        child: Text(
                          '章节状态',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ..._buildChapterStatusList(),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text('生成日志', style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(height: 8),
                      _buildLogView(theme),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonitoringCards(ThemeData theme) {
    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
            title: Center(
              child: Text(
                _mainStatus,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            dense: true,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              Icons.history_toggle_off,
              color: theme.colorScheme.secondary,
            ),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Text(
                _detailedStatus,
                key: ValueKey<String>(_detailedStatus),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            dense: true,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildChapterStatusList() {
    final storyline = List<Map<String, dynamic>>.from(
      widget.outline['storyline'],
    );
    return List.generate(_chapterInfos.length, (index) {
      final info = _chapterInfos[index];
      final chapterTitle = storyline[index]['chapter_title'] ?? '未命名章节';

      Widget leading;
      Color statusColor;
      String statusText;

      switch (info.status) {
        case ChapterStatus.pending:
          statusColor = Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.6);
          leading = Icon(Icons.hourglass_empty, color: statusColor);
          statusText = '等待中';
          break;
        case ChapterStatus.planning:
          statusColor = Theme.of(context).colorScheme.tertiary;
          leading = SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: statusColor,
            ),
          );
          statusText = '规划剧情中...';
          break;
        case ChapterStatus.generating:
          statusColor = Theme.of(context).colorScheme.primary;
          leading = SizedBox(
            width: 40,
            height: 40,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: info.progress),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, child) {
                return Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: value,
                      strokeWidth: 3,
                      color: statusColor,
                    ),
                    Center(
                      child: Text(
                        '${(value * 100).round()}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
          statusText = '生成中...';
          break;
        case ChapterStatus.completed:
          statusColor = Colors.green.shade600;
          leading = Icon(Icons.check_circle, color: statusColor);
          statusText = '已完成';
          break;
        case ChapterStatus.error:
          statusColor = Theme.of(context).colorScheme.error;
          leading = Icon(Icons.error, color: statusColor);
          statusText = '失败';
          break;
      }

      Widget? buildTrailingActions() {
        if (_isSaving ||
            _isTerminated ||
            info.status == ChapterStatus.generating ||
            info.status == ChapterStatus.planning) {
          return null;
        }

        final bool planExists = NovelGeneratorService.instance.hasChapterPlan(
          widget.outline['title'],
          index,
        );

        final actions = <Widget>[];

        if (planExists &&
            (info.status == ChapterStatus.pending ||
                info.status == ChapterStatus.error)) {
          actions.add(
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: '从断点继续生成',
              onPressed: () => _continueChapter(index),
            ),
          );
        }

        if (info.status == ChapterStatus.error ||
            info.status == ChapterStatus.completed) {
          actions.add(
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新生成本章',
              onPressed: () => _regenerateChapter(index),
            ),
          );
        }

        if (actions.isEmpty) {
          return null;
        }

        return Row(mainAxisSize: MainAxisSize.min, children: actions);
      }

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.1),
            child: leading,
          ),
          title: Text(
            '第 ${index + 1} 章: $chapterTitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (info.charCount > 0)
                  TextSpan(
                    text: ' - 约 ${info.charCount} 字',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          trailing: buildTrailingActions(),
          dense: true,
        ),
      );
    });
  }

  Widget _buildActionButtons() {
    if (_isSaving) {
      return FilledButton.icon(
        onPressed: null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        label: const Text('保存中...'),
      );
    }

    if (_isFinished) {
      final canSave = _hasSavableChapterContent;
      final isCompleteSave =
          !_hasError &&
          !_isTerminated &&
          _allChaptersCompleted &&
          _savableChapterCount == _chapterInfos.length;
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: Icon(
            canSave
                ? (isCompleteSave ? Icons.check_circle_outline : Icons.save_alt)
                : Icons.arrow_back,
          ),
          label: Text(canSave ? (isCompleteSave ? '完成并保存' : '保存已生成内容') : '返回'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: canSave
                ? null
                : Theme.of(context).colorScheme.errorContainer,
            foregroundColor: canSave
                ? null
                : Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: () {
            if (canSave) {
              _saveGeneratedBook();
            } else {
              Navigator.of(context).pop(false);
            }
          },
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('终止任务'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
          ),
        ),
        onPressed: _terminateTask,
      ),
    );
  }

  Widget _buildProgressIndicator(Color progressColor, ThemeData theme) {
    return SizedBox(
      width: 120,
      height: 120,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _progress),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: progressColor.withValues(alpha: 0.2),
                color: progressColor,
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isFinished && !_hasError && !_isTerminated)
                      Icon(Icons.check_circle, color: progressColor, size: 40)
                    else if (_hasError || _isTerminated)
                      Icon(Icons.error, color: progressColor, size: 40)
                    else
                      Text(
                        '${(value * 100).round()}%',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: progressColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 增加独立滚动条的日志视图
  Widget _buildLogView(ThemeData theme) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: Scrollbar(
        controller: _logScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _logScrollController,
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            final log = _logs[index];
            final time =
                '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    log.icon,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text('[$time]', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(log.message, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
