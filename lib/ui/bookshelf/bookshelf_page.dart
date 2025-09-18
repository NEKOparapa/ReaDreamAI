// lib/ui/bookshelf/bookshelf_page.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tiktoken/tiktoken.dart';
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
        final newEntry = await FileParser.parseAndCreateCache(path);
        if (newEntry != null) {
          if (!_entries.any((e) => e.id == newEntry.id)) {
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

  // ---------- 方法改进：在文本编辑栏上面加个书籍名输入栏 ----------
  void _showPasteImportDialog() {
    // 创建两个控制器
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    
    final screenSize = MediaQuery.of(context).size;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴文本导入'),
          // 使用 SizedBox 约束整体大小
          content: SizedBox(
            width: screenSize.width * 0.8,
            height: screenSize.height * 0.7,
            // 使用 Column 垂直排列书名输入框和内容输入框
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 书名输入框
                TextField(
                  controller: titleController,
                  autofocus: true, // 自动聚焦，方便用户直接输入
                  decoration: const InputDecoration(
                    labelText: '书籍名',
                    hintText: '请输入书籍名称（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16), // 增加间距
                // 内容输入框，使用 Expanded 填满剩余空间
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null, // 无限行
                    expands: true, // 填满父组件 (Expanded)
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: '在此处粘贴您的文本内容...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('确认导入'),
              onPressed: () {
                // 获取两个输入框的内容
                final bookTitle = titleController.text;
                final pastedText = contentController.text;
                Navigator.of(context).pop();
                if (pastedText.trim().isNotEmpty) {
                  // 将书名和内容都传递给处理函数
                  _importPastedText(bookTitle, pastedText);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ---------- 方法改进：接收用户输入的书名 ----------
  Future<void> _importPastedText(String titleInput, String content) async {
    try {
      final tempDir = await getTemporaryDirectory();

      // ---------- 关键改动：决定最终使用的书名 ----------
      // 1. 优先使用用户输入的书名（去除首尾空格后）
      // 2. 如果用户未输入，则回退到旧逻辑：从内容第一行提取
      String title = titleInput.trim();
      if (title.isEmpty) {
        title = content.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '无标题文本').trim();
        if (title.length > 40) {
          title = title.substring(0, 40);
        }
      }
      
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final uniqueId = const Uuid().v4().substring(0, 8);
      // 使用最终确定的书名来创建文件名
      final fileName = '$sanitizedTitle-$uniqueId.txt';
      final filePath = p.join(tempDir.path, fileName);
      
      final file = File(filePath);
      await file.writeAsString(content);

      // 调用文件处理流程
      await _processFiles([filePath]);

    } catch (e) {
      if (mounted) {
        _showTopMessage('粘贴导入失败: $e', isError: true);
      }
    }
  }
  
  // 省略其他未改动的方法: _generateIllustrations, _splitBookIntoTaskChunks, 等...
  // ... (为了简洁，这里省略了未改动的代码，实际使用时请保留)
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
        actions: const [],
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
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _addBooksWithPicker,
            tooltip: '导入文件',
            heroTag: 'import_file',
            child: const Icon(Icons.file_open),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            onPressed: _showPasteImportDialog,
            tooltip: '粘贴导入',
            heroTag: 'paste_import',
            child: const Icon(Icons.paste),
          ),
        ],
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
          Text('拖入文件或点击右下角按钮添加书籍',
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
        childAspectRatio: 2 / 3.2,
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
              flex: 4,
              child: hasCover
                  ? Image.file(
                      File(entry.coverImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCoverPlaceholder(entry);
                      },
                    )
                  : _buildCoverPlaceholder(entry),
            ),
            Container(
              height: 35,
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(BookshelfEntry entry) {
    final colors = [
      Colors.deepPurple, Colors.teal, Colors.indigo,
      Colors.brown, Colors.blueGrey, Colors.redAccent
    ];
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