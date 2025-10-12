import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/book.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../models/character_card_model.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/task_executor/novel_generator_service.dart';

// 定义章节状态
enum ChapterStatus { pending, generating, completed, error }

// 定义日志模型
class GenerationLog {
  final DateTime timestamp;
  final String message;
  final IconData icon;

  GenerationLog(this.message, this.icon) : timestamp = DateTime.now();
}

class NovelGenerationProgressPage extends StatefulWidget {
  final Map<String, dynamic> outline;

  const NovelGenerationProgressPage({
    super.key,
    required this.outline,
  });

  @override
  State<NovelGenerationProgressPage> createState() =>
      _NovelGenerationProgressPageState();
}

class _NovelGenerationProgressPageState extends State<NovelGenerationProgressPage> {
  final _configService = ConfigService();
  double _progress = 0.0;
  String _mainStatus = '准备就绪...';
  String _detailedStatus = '即将开始生成流程';
  final List<GenerationLog> _logs = [];
  bool _isFinished = false;
  bool _hasError = false;
  bool _isTerminated = false;

  late List<ChapterStatus> _chapterStatuses;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chapterStatuses = List.generate(
      widget.outline['storyline'].length,
      (_) => ChapterStatus.pending,
    );
    Future.microtask(() => startGeneration());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String message, IconData icon) {
    if (mounted) {
      setState(() {
        _logs.add(GenerationLog(message, icon));
      });
      Timer(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> startGeneration() async {
    LogService.instance.info('开始并行生成小说正文...');
    _addLog('生成任务已启动', Icons.play_circle_outline);
    setState(() {
      _mainStatus = '正在并行生成所有章节...';
      _detailedStatus = '任务已分发';
    });
    
    final wordsPerChapter = _configService.getSetting<int>('ai_novel_creation_words_per_chapter', 1500);
    LogService.instance.info('获取到用户设定的每章字数: $wordsPerChapter');
    _addLog('目标字数设定为每章约 $wordsPerChapter 字', Icons.format_size);

    final llmApi = _configService.getActiveLanguageApi();
    final concurrency = llmApi.concurrencyLimit ?? 3; // 默认并发数为3
    final pool = Pool(concurrency);
    LogService.instance.info('启动小说生成任务池，最大并发数: $concurrency');

    try {
      final storyline = List<Map<String, dynamic>>.from(widget.outline['storyline']);
      final characters = List<Map<String, dynamic>>.from(widget.outline['main_characters']);
      final chapterContents = List<String?>.filled(storyline.length, null);
      final futures = <Future>[];
      int completedChapters = 0;

      for (int i = 0; i < storyline.length; i++) {
        futures.add(pool.withResource(() async {
          if (_isTerminated || !mounted) return;

          setState(() {
            _chapterStatuses[i] = ChapterStatus.generating;
          });
          _addLog('开始生成第 ${i + 1} 章: "${storyline[i]['chapter_title']}"...', Icons.cloud_upload_outlined);

          try {
            final content = await NovelGeneratorService.instance.generateChapterContent(
              title: widget.outline['title'],
              backgroundSetting: widget.outline['background_setting'],
              writingStyle: widget.outline['writing_style'],
              mainCharacters: characters,
              storyline: storyline,
              chapterIndex: i,
              wordsPerChapter: wordsPerChapter, 
              onProgress: (message) {
                // 当服务层有新的进度时，更新UI
                if (mounted && !_isTerminated) {
                  setState(() {
                    _detailedStatus = '第 ${i + 1} 章: $message';
                  });
                }
              },
            );
            
            if (_isTerminated || !mounted) return;
            
            chapterContents[i] = content;
            _addLog('第 ${i + 1} 章内容已成功接收', Icons.cloud_download_outlined);

            if (mounted) {
              setState(() {
                completedChapters++;
                _chapterStatuses[i] = ChapterStatus.completed;
                _progress = completedChapters / storyline.length;
                _mainStatus = '正在创作 ($completedChapters/${storyline.length})';
                _detailedStatus = '“${storyline[i]['chapter_title']}” 已完成';
              });
            }
          } catch (e, s) {
            if (_isTerminated || !mounted) return;
            LogService.instance.error('生成第 ${i + 1} 章时失败', e, s);
            _addLog('第 ${i + 1} 章生成失败: $e', Icons.error_outline);
            if (mounted) {
              setState(() {
                _chapterStatuses[i] = ChapterStatus.error;
                _hasError = true;
              });
            }
          }
        }));
      }

      await Future.wait(futures);

      if (_isTerminated) {
        _addLog('任务已被用户手动终止', Icons.cancel_outlined);
        setState(() {
          _mainStatus = '任务已终止';
          _detailedStatus = '生成过程已停止';
          _isFinished = true;
        });
        return;
      }
      
      if (_hasError) {
        throw Exception('一个或多个章节生成失败。');
      }

      if (!mounted) return;
      _addLog('所有章节已生成，正在整理成书...', Icons.menu_book_outlined);
      setState(() {
        _mainStatus = '正在保存书籍';
        _detailedStatus = '编译章节内容...';
      });
      
      // 按顺序组装书籍
      final List<ChapterStructure> finalChapters = [];
      final fullTextBuilder = StringBuffer();
      int globalLineIdCounter = 0;

      for (int i = 0; i < storyline.length; i++) {
        final content = chapterContents[i]!;
        fullTextBuilder.write("## ${storyline[i]['chapter_title']}\n\n$content\n\n---\n\n");
        
        final chapterLines = _createLines(content, 'content.txt', globalLineIdCounter);
        final newChapter = ChapterStructure(
          id: const Uuid().v4(),
          title: storyline[i]['chapter_title'],
          sourceFile: 'content.txt',
          lines: chapterLines,
          chapterSummary: storyline[i]['chapter_summary'], // 保留原有简述
        );
        finalChapters.add(newChapter);
        globalLineIdCounter += chapterLines.length;
      }

      await _saveBook(finalChapters, fullTextBuilder.toString());

      if (mounted) {
        _addLog('《${widget.outline['title']}》已成功保存到书架！', Icons.check_circle_outline);
        setState(() {
          _mainStatus = '生成成功！';
          _detailedStatus = '您的新书已在书架上等您';
          _isFinished = true;
        });
      }
    } catch (e, s) {
      LogService.instance.error('小说正文生成过程中发生错误', e, s);
      if (!_hasError) _addLog('发生严重错误: $e', Icons.error_outline);
      if (mounted) {
        setState(() {
          _mainStatus = '生成失败';
          _detailedStatus = '请检查日志或网络连接后重试';
          _hasError = true;
          _isFinished = true;
        });
      }
    }
  }

  List<LineStructure> _createLines(String content, String sourceFilename, int startLineId) {
    final List<LineStructure> result = [];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    int lineId = startLineId;
    for (final lineText in lines) {
      if (lineText.trim().isNotEmpty) {
        result.add(LineStructure(
          id: lineId++,
          text: lineText.trim(),
          sourceInfo: sourceFilename,
          originalContent: lineText,
        ));
      }
    }
    return result;
  }

  Future<void> _saveBook(List<ChapterStructure> chapters, String fullTextContent) async {
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
    final (String bookId, String cachedPath, _) =
        await cacheManager.createBookCacheInfrastructure(tempFilePath);
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
      onWillPop: () async => _isFinished,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isFinished ? '生成完成' : '正在生成小说...'),
          // 终止或完成后，显示返回按钮
          automaticallyImplyLeading: _isFinished,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _buildProgressIndicator(progressColor, theme)),
                const SizedBox(height: 16),
                Text(
                  _mainStatus,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _detailedStatus,
                    key: ValueKey<String>(_detailedStatus),
                    style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                _buildChapterStatusTracker(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('生成日志', style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                _buildLogView(theme),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChapterStatusTracker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            '章节进度',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: List.generate(_chapterStatuses.length, (index) {
              final status = _chapterStatuses[index];
              IconData icon;
              Color color;

              switch (status) {
                case ChapterStatus.pending:
                  icon = Icons.hourglass_empty;
                  color = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
                  break;
                case ChapterStatus.generating:
                  icon = Icons.autorenew;
                  color = Theme.of(context).colorScheme.primary;
                  break;
                case ChapterStatus.completed:
                  icon = Icons.check_circle;
                  color = Colors.green.shade600;
                  break;
                case ChapterStatus.error:
                  icon = Icons.error;
                  color = Theme.of(context).colorScheme.error;
                  break;
              }

              return Chip(
                avatar: status == ChapterStatus.generating 
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color,))
                  : Icon(icon, color: color, size: 18),
                label: Text('第 ${index + 1} 章'),
                labelStyle: TextStyle(color: color),
                side: BorderSide(color: color.withOpacity(0.5)),
                backgroundColor: color.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_isFinished) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: Icon(_hasError || _isTerminated ? Icons.arrow_back : Icons.done_all),
          label: Text(_hasError || _isTerminated ? '返回' : '完成'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _hasError ? Theme.of(context).colorScheme.error : null
          ),
          onPressed: () {
            Navigator.of(context).pop(!_hasError && !_isTerminated);
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
          side: BorderSide(color: Theme.of(context).colorScheme.error.withOpacity(0.5)),
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
        tween: Tween<double>(begin: _progress, end: _progress), // Use _progress for both to avoid re-animating
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: progressColor.withOpacity(0.2),
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

  Widget _buildLogView(ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            final log = _logs[index];
            final time = '${log.timestamp.hour.toString().padLeft(2,'0')}:${log.timestamp.minute.toString().padLeft(2,'0')}:${log.timestamp.second.toString().padLeft(2,'0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(log.icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('[$time]', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  Expanded(child: Text(log.message, style: theme.textTheme.bodyMedium)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}