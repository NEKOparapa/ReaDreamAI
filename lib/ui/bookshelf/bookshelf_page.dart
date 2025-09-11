// lib/ui/bookshelf/bookshelf_page.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:tiktoken/tiktoken.dart'; // 用于计算token
import 'package:uuid/uuid.dart';

// 导入项目内部的文件
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/file_parser/file_parser.dart';
import '../../base/config_service.dart';
import '../reader/book_reader.dart';
import '../../services/task_manager/task_manager_service.dart';
import '../../services/epub_exporter/epub_exporter.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final List<BookshelfEntry> _entries = [];
  bool _isDragging = false;
  bool _isProcessing = false;
  bool _isLoadingFromCache = true;

  @override
  void initState() {
    super.initState();
    _loadBookshelf();
  }

  Future<void> _loadBookshelf() async {
    final cachedEntries = await CacheManager().loadBookshelf();
    if (mounted) {
      setState(() {
        _entries.clear();
        _entries.addAll(cachedEntries);
        _isLoadingFromCache = false;
      });
    }
  }

  Future<void> _saveBookshelf() async {
    await CacheManager().saveBookshelf(_entries);
  }

  Future<void> _processFiles(List<String> paths) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final controller = _showTopMessage('正在处理文件...',
        leading: const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        duration: const Duration(minutes: 5));

    int newBookCount = 0;
    for (final path in paths) {
      final fileExtension = p.extension(path).toLowerCase();
      if (['.txt', '.epub'].contains(fileExtension)) {
        if (!_entries.any((e) => e.originalPath == path)) {
          final newEntry = await FileParser.parseAndCreateCache(path);
          if (newEntry != null) {
            _entries.add(newEntry);
            newBookCount++;
          }
        }
      }
    }

    if (newBookCount > 0) {
      await _saveBookshelf();
      setState(() {});
    }

    controller.close();
    setState(() => _isProcessing = false);

    if (mounted && newBookCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功添加 $newBookCount 本书')),
      );
    }
  }

  void _onDragDone(DropDoneDetails details) async {
    setState(() => _isDragging = false);
    final paths = details.files.map((file) => file.path).toList();
    await _processFiles(paths);
  }

  void _addBooksWithPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
      allowMultiple: true,
    );
    if (result != null && result.paths.isNotEmpty) {
      final paths = result.paths.whereType<String>().toList();
      await _processFiles(paths);
    }
  }

  Future<void> _exportCacheData() async {
    final String? outputFolder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '请选择导出缓存数据的文件夹',
    );
    if (outputFolder != null) {
      final outputFile = File(p.join(outputFolder, 'bookshelf_data_export.json'));
      try {
        final jsonString = const JsonEncoder.withIndent('  ').convert(_entries);
        await outputFile.writeAsString(jsonString);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('数据已成功导出到: ${outputFile.path}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _generateIllustrations(BookshelfEntry entry) async {
    final book = await CacheManager().loadBookDetail(entry.id);
    if (book == null) {
      _showTopMessage('错误：找不到书籍数据', isError: true);
      return;
    }
    final chunks = _splitBookIntoTaskChunks(book);
    if (chunks.isEmpty) {
      _showTopMessage('书籍内容为空，无法创建任务');
      return;
    }
    setState(() {
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index != -1) {
        _entries[index].taskChunks = chunks;
        _entries[index].status = TaskStatus.queued;
        _entries[index].createdAt = DateTime.now();
        _entries[index].updatedAt = DateTime.now();
        _entries[index].errorMessage = null;
      }
    });
    await _saveBookshelf();
    await TaskManagerService.instance.reloadData();
    TaskManagerService.instance.processQueue();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已为《${entry.title}》创建 ${chunks.length} 个生成子任务'),
        action: SnackBarAction(
            label: '查看任务',
            onPressed: () {
              // TODO: 跳转到任务页面的逻辑
            }),
      ),
    );
  }

  List<IllustrationTaskChunk> _splitBookIntoTaskChunks(Book book) {
    final config = ConfigService();
    final scenesPerChapter = config.getSetting<int>('image_gen_scenes_per_chapter', 3);
    final maxChunkTokens = config.getSetting<int>('image_gen_tokens', 5000);
    final List<IllustrationTaskChunk> allChunks = [];
    final encoding = encodingForModel("gpt-4");
    for (final chapter in book.chapters) {
      if (chapter.lines.isEmpty) continue;
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
            id: const Uuid().v4(),
            chapterTitle: chapter.title,
            startLineId: chunkLines.first.id,
            endLineId: chunkLines.last.id,
            scenesToGenerate: scenesPerChunk[i],
          ));
        }
      }
    }
    return allChunks;
  }

  Future<void> _generateTranslations(BookshelfEntry entry) async {
    final book = await CacheManager().loadBookDetail(entry.id);
    if (book == null) {
      _showTopMessage('错误：找不到书籍数据', isError: true);
      return;
    }
    final chunks = _splitBookIntoTranslationChunks(book);
    if (chunks.isEmpty) {
      _showTopMessage('书籍内容为空，无法创建任务');
      return;
    }
    setState(() {
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index != -1) {
        _entries[index].translationTaskChunks = chunks;
        _entries[index].translationStatus = TaskStatus.queued;
        _entries[index].translationCreatedAt = DateTime.now();
        _entries[index].translationUpdatedAt = DateTime.now();
        _entries[index].translationErrorMessage = null;
      }
    });
    await _saveBookshelf();
    await TaskManagerService.instance.reloadData();
    TaskManagerService.instance.processQueue();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已为《${entry.title}》创建 ${chunks.length} 个翻译子任务'),
        action: SnackBarAction(
            label: '查看任务',
            onPressed: () {
              // TODO: 跳转到任务页面的逻辑
            }),
      ),
    );
  }

  List<TranslationTaskChunk> _splitBookIntoTranslationChunks(Book book) {
    final config = ConfigService();
    final maxChunkTokens = config.getSetting<int>('translation_tokens', 4000);
    final List<TranslationTaskChunk> allChunks = [];
    final encoding = encodingForModel("gpt-4");
    for (final chapter in book.chapters) {
      if (chapter.lines.isEmpty) continue;
      List<LineStructure> currentChunkLines = [];
      int currentTokens = 0;
      for (final line in chapter.lines) {
        final lineTokens = encoding.encode(line.text).length;
        if (currentTokens + lineTokens > maxChunkTokens && currentChunkLines.isNotEmpty) {
          allChunks.add(TranslationTaskChunk(
            id: const Uuid().v4(),
            chapterTitle: chapter.title,
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
          id: const Uuid().v4(),
          chapterTitle: chapter.title,
          startLineId: currentChunkLines.first.id,
          endLineId: currentChunkLines.last.id,
        ));
      }
    }
    return allChunks;
  }

  void _deleteBook(BookshelfEntry entry) async {
    final bookTitle = entry.title;
    TaskManagerService.instance.deleteTask(entry.id);
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
    await CacheManager().removeBookCacheFolder(entry.id);
    await _saveBookshelf();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('《$bookTitle》已删除')),
      );
    }
  }

  void _openBook(BookshelfEntry entry) async {
    final book = await CacheManager().loadBookDetail(entry.id);
    if (book != null && mounted) {
      // 统一导航到 BookReaderPage
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => BookReaderPage(book: book)),
      );
    } else {
      _showTopMessage('加载书籍详情失败', isError: true);
    }
  }

  void _showContextMenu(
      BuildContext context, BookshelfEntry entry, TapDownDetails details) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
          details.globalPosition & const Size(40, 40), Offset.zero & overlay.size),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          enabled: entry.status == TaskStatus.notStarted ||
              entry.status == TaskStatus.failed ||
              entry.status == TaskStatus.canceled,
          onTap: () => _generateIllustrations(entry),
          child: const Row(children: [
            Icon(Icons.auto_awesome, color: Colors.blue),
            SizedBox(width: 8),
            Text('生成插图')
          ]),
        ),
        PopupMenuItem(
          enabled: entry.translationStatus == TaskStatus.notStarted ||
              entry.translationStatus == TaskStatus.failed ||
              entry.translationStatus == TaskStatus.canceled,
          onTap: () => _generateTranslations(entry),
          child: const Row(children: [
            Icon(Icons.translate, color: Colors.green),
            SizedBox(width: 8),
            Text('生成翻译')
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => _exportBook(entry),
          child: const Row(
            children: [
              Icon(Icons.import_export, color: Colors.orange),
              SizedBox(width: 8),
              Text('导出书籍')
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _deleteBook(entry),
          child: const Text('删除书籍', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Future<void> _exportBook(BookshelfEntry entry) async {
    try {
      final book = await CacheManager().loadBookDetail(entry.id);
      if (book != null) {
        await EpubExporter.exportBook(book);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('书籍导出成功！')),
          );
        }
      }
    } catch (e) {
      _showTopMessage('导出失败：$e', isError: true);
      print('导出失败：$e');
    }
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showTopMessage(
    String message, {
    Widget? leading,
    Duration duration = const Duration(seconds: 4),
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(child: Text(message, overflow: TextOverflow.ellipsis)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: MediaQuery.of(context).size.width * 0.3,
          right: MediaQuery.of(context).size.width * 0.3,
        ),
        backgroundColor:
            isError ? Colors.red.withOpacity(0.9) : Colors.black.withOpacity(0.8),
        duration: duration,
        showCloseIcon: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书架'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加书籍',
              onPressed: _addBooksWithPicker),
          IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              tooltip: '导出缓存数据',
              onPressed: _exportCacheData),
          const SizedBox(width: 8),
        ],
      ),
      body: DropTarget(
        onDragDone: _onDragDone,
        onDragEntered: (details) => setState(() => _isDragging = true),
        onDragExited: (details) => setState(() => _isDragging = false),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: _isDragging
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 3),
            color: _isDragging
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
          ),
          padding: const EdgeInsets.all(20.0),
          child: _entries.isEmpty && !_isLoadingFromCache
              ? _buildEmptyState()
              : _buildBookshelfGrid(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('拖入 TXT/EPUB 文件或点击右上角添加',
              style:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
          SizedBox(height: 8),
          Text('开始你的阅读之旅', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBookshelfGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 2 / 3.2, // 调整宽高比以适应新的布局
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _buildBookItem(entry);
      },
    );
  }

  Widget _buildBookItem(BookshelfEntry entry) {
    // 检查封面图片是否存在
    final hasCover =
        entry.coverImagePath != null && File(entry.coverImagePath!).existsSync();

    return GestureDetector(
      onTap: () => _openBook(entry),
      onSecondaryTapDown: (details) => _showContextMenu(context, entry, details),
      child: Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4, // 调整封面和标题的比例，让封面更大
              child: hasCover
                  ? Image.file(
                      // 如果有封面，显示图片
                      File(entry.coverImagePath!),
                      fit: BoxFit.cover,
                      // 添加错误处理，以防图片文件损坏
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCoverPlaceholder(entry);
                      },
                    )
                  : _buildCoverPlaceholder(entry), // 如果没有，显示占位符
            ),
            Container(
              // 将标题部分包裹在Container中以便更好地控制样式
              height: 50, // 给标题部分一个固定的高度
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1, // 只显示一行
                    overflow: TextOverflow.ellipsis, // 超出部分显示省略号
                    textAlign: TextAlign.start, // 文本左对齐
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增一个构建封面占位符的辅助方法，提高代码复用性
  Widget _buildCoverPlaceholder(BookshelfEntry entry) {
    final colors = [
      Colors.deepPurple, Colors.teal, Colors.indigo,
      Colors.brown, Colors.blueGrey, Colors.redAccent
    ];
    // 使用书籍ID的哈希码来选择一个稳定的颜色，这样同一本书的占位符颜色总是一样的
    final color = colors[entry.id.hashCode % colors.length];

    return Container(
      color: color[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 50, color: Colors.white.withOpacity(0.8)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                entry.title,
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            )
          ],
        ),
      ),
    );
  }
}