// lib/ui/bookshelf/bookshelf_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// 导入项目内部的文件
import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/file_parser/file_parser.dart';
import '../../services/task_manager/task_manager_service.dart';
import '../../base/log/log_service.dart';

// 导入相关页面
import '../reader/novel_book/book_reader.dart';
import '../reader/video_book_reader.dart';
import '../reader/game_book/game_book_reader_page.dart';

// 导入功能弹窗
import 'generate_illustration_dialog.dart';
import 'generate_translation_dialog.dart';
import 'generate_video_dialog.dart';
import 'export_book_dialog.dart';

/// 书架页面 StatefulWidget
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

/// 书架页面的状态管理类
class _BookshelfPageState extends State<BookshelfPage> with WidgetsBindingObserver {
  // 书架上的书籍条目列表
  final List<BookshelfEntry> _entries = [];
  // 标记是否有文件拖拽进入UI区域
  bool _isDragging = false;
  // 标记是否正在处理文件，防止重复操作
  bool _isProcessing = false;
  // 标记是否正在从缓存加载数据，用于显示加载状态
  bool _isLoadingFromCache = true;

  @override
  void initState() {
    super.initState();
    // 添加生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    // 页面初始化时加载书架数据
    _loadBookshelf();
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 监听应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台恢复到前台时，刷新书架
    if (state == AppLifecycleState.resumed) {
      _loadBookshelf();
    }
  }

  // 每次页面重新构建时检查是否需要刷新
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当路由变化时（比如从其他页面返回），刷新书架
    _loadBookshelf();
  }

  /// 从缓存加载书架数据
  Future<void> _loadBookshelf() async {
    final cachedEntries = await CacheManager().loadBookshelf();
    // 检查组件是否还在树中，避免在已销毁的组件上调用setState
    if (mounted) {
      setState(() {
        _entries.clear();
        _entries.addAll(cachedEntries);
        _isLoadingFromCache = false;
      });
    }
  }

  /// 保存当前书架数据到缓存
  Future<void> _saveBookshelf() async {
    await CacheManager().saveBookshelf(_entries);
  }

  /// 处理文件（来自拖拽或文件选择器）
  Future<void> _processFiles(List<String> paths) async {
    if (_isProcessing) return; // 如果正在处理，则直接返回
    setState(() => _isProcessing = true);

    int newBookCount = 0;
    try {
      for (final path in paths) {
        final fileExtension = p.extension(path).toLowerCase();
        // 只处理 .txt 和 .epub 文件
        if (['.txt', '.epub'].contains(fileExtension)) {
          // 解析文件并创建缓存
          final newEntry = await FileParser.parseAndCreateCache(path);
          if (newEntry != null) {
            // 如果书架中不存在这本书，则添加
            if (!_entries.any((e) => e.id == newEntry.id)) {
              _entries.add(newEntry);
              newBookCount++;
            }
          }
        }
      }

      // 如果有新书添加，则保存书架并更新UI
      if (newBookCount > 0) {
        await _saveBookshelf();
        setState(() {});
      }

      // 如果组件挂载且有新书添加，显示成功提示
      if (mounted && newBookCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功添加 $newBookCount 本书')),
        );
      }
    } finally {
      // 确保处理标志在操作完成后被重置
      if(mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  /// 拖拽文件完成后的回调
  void _onDragDone(DropDoneDetails details) async {
    setState(() => _isDragging = false);
    final paths = details.files.map((file) => file.path).toList();
    await _processFiles(paths);
  }

  /// 通过文件选择器添加书籍
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

  /// 显示粘贴导入对话框
  void _showPasteImportDialog() {
    // 创建两个文本控制器，用于获取输入框内容
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final screenSize = MediaQuery.of(context).size;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴文本导入'),
          // 使用 SizedBox 约束对话框整体大小
          content: SizedBox(
            width: screenSize.width * 0.8,
            height: screenSize.height * 0.7,
            // 使用 Column 垂直排列
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 书名输入框
                TextField(
                  controller: titleController,
                  autofocus: true, // 自动聚焦
                  decoration: const InputDecoration(
                    labelText: '书籍名',
                    hintText: '请输入书籍名称（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16), // 间距
                // 内容输入框，使用 Expanded 填满剩余空间
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null, // 无限行
                    expands: true, // 填满父组件
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
                final bookTitle = titleController.text;
                final pastedText = contentController.text;
                Navigator.of(context).pop();
                if (pastedText.trim().isNotEmpty) {
                  // 将内容传递给处理函数
                  _importPastedText(bookTitle, pastedText);
                }
              },
            ),
          ],
        );
      },
    );
  }

  /// 将粘贴的文本导入为一本书
  Future<void> _importPastedText(String titleInput, String content) async {
    try {
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      String title = titleInput.trim();
      // 如果用户未输入标题，则自动从内容第一行生成
      if (title.isEmpty) {
        title = content
            .trim()
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '无标题文本')
            .trim();
        if (title.length > 40) {
          title = title.substring(0, 40);
        }
      }

      // 清理文件名中的非法字符
      final sanitizedTitle = title.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
      final uniqueId = const Uuid().v4().substring(0, 8); // 添加唯一ID防止重名
      final fileName = '$sanitizedTitle-$uniqueId.txt';
      final filePath = p.join(tempDir.path, fileName);

      // 将内容写入临时文件
      final file = File(filePath);
      await file.writeAsString(content);

      // 调用标准的文件处理流程
      await _processFiles([filePath]);
    } catch (e, s) {
      LogService.instance.error('粘贴导入失败', e, s);
      if (mounted) {
        _showTopMessage('粘贴导入失败: $e', isError: true);
      }
    }
  }

  /// 为指定书籍生成插图任务
  Future<void> _generateIllustrations(BookshelfEntry entry) async {
    // 显示配置对话框，并等待其返回结果
    final bool? taskCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenerateIllustrationDialog(entry: entry),
    );

    // 如果对话框返回true，说明任务已成功创建
    if (taskCreated == true && mounted) {
      // 重新从缓存加载书架数据，以更新UI状态（例如显示"排队中"）
      await _loadBookshelf();

      // 找到更新后的条目，以获取正确的任务信息用于提示
      final updatedEntry = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已为《${updatedEntry.title}》创建 ${updatedEntry.taskChunks.length} 个生成子任务'),
        ),
      );
    }
  }

  /// 为指定书籍生成翻译任务
  Future<void> _generateTranslations(BookshelfEntry entry) async {
    // 显示配置对话框，并等待其返回结果
    final bool? taskCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenerateTranslationDialog(entry: entry),
    );

    // 如果对话框返回true，说明任务已成功创建
    if (taskCreated == true && mounted) {
      // 重新从缓存加载书架数据，以更新UI状态（例如显示"排队中"）
      await _loadBookshelf();

      // 找到更新后的条目，以获取正确的任务信息用于提示
      final updatedEntry = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已为《${updatedEntry.title}》创建 ${updatedEntry.translationTaskChunks.length} 个翻译子任务'),
        ),
      );
    }
  }

  Future<void> _generateVideosFromImages(BookshelfEntry entry) async {
    final bool? taskCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenerateVideoDialog(entry: entry),
    );
    if (taskCreated == true && mounted) {
      await _loadBookshelf();
      final updatedEntry = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry,
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已为《${updatedEntry.title}》创建 ${updatedEntry.videoGenerationTaskChunks.length} 个视频生成子任务'),
        ),
      );
    }
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
    // 游戏书类型跳转
    if (entry.fileType == 'gameBook') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => GameBookReaderPage(entry: entry),
        ),
      );
      return; 
    }

    // 视频书类型跳转
    if (entry.fileType == 'videoBook') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoBookReaderPage(entry: entry),
        ),
      );
      return;
    }

    // 普通文本/EPUB书跳转
    final book = await CacheManager().loadBookDetail(entry.id);
    if (book != null && mounted) {
      // 在跳转到 BookReaderPage 时，传入记录的章节索引
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => BookReaderPage(
          book: book,
          initialChapterIndex: entry.lastReadChapterIndex, // 传递进度
        )),
      );
      await _loadBookshelf();
    } else {
      _showTopMessage('加载书籍详情失败', isError: true);
    }
  }

  void _showContextMenu(
        BuildContext context, BookshelfEntry entry, Offset globalPosition) {
      final RenderBox overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      showMenu(
        context: context,
        position: RelativeRect.fromRect(
            globalPosition & const Size(40, 40), Offset.zero & overlay.size),
        items: <PopupMenuEntry>[

          if (entry.fileType != 'videoBook' && entry.fileType != 'gameBook') ...[
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
              enabled: true,
              onTap: () => _generateVideosFromImages(entry),
              child: const Row(children: [
                Icon(Icons.video_library, color: Colors.purple),
                SizedBox(width: 8),
                Text('图生视频')
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
            // 分隔线，仅在有生成选项时显示
            const PopupMenuDivider(),
          ],
          
          if (entry.fileType != 'gameBook') 
            PopupMenuItem(
              onTap: () => _showExportDialog(entry),
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
            child: const Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('删除书籍') // 或者根据你的需求改成 '删除数据'
              ],
            ),
          ),
        ],
      );
    }

  Future<void> _showExportDialog(BookshelfEntry entry) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // 导出过程中不允许点击外部关闭
      builder: (context) => ExportBookDialog(entry: entry),
    );
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
            isError ? Colors.red.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.8),
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
            icon: const Icon(Icons.refresh),
            tooltip: '刷新书架',
            onPressed: _loadBookshelf,
          ),
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
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          padding: const EdgeInsets.all(20.0),
          child: _isLoadingFromCache
              ? const Center(child: CircularProgressIndicator())
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

  /// 构建书架网格视图
  Widget _buildBookshelfGrid() {
    // 如果书架为空，显示提示信息
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '书架为空',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '拖拽文件到此窗口，或使用右下角按钮导入书籍',
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

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

  /// 构建单个书籍封面的UI
  Widget _buildBookItem(BookshelfEntry entry) {
    final hasCover =
        entry.coverImagePath != null && File(entry.coverImagePath!).existsSync();

    return GestureDetector(
      onTap: () => _openBook(entry),
      // for Windows/Desktop: 响应右键点击
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, entry, details.globalPosition),
      // for Android/Mobile: 响应长按
      onLongPressStart: (details) =>
          _showContextMenu(context, entry, details.globalPosition),
      child: Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
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
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // 如果是视频书，在右上角显示一个图标
            if (entry.fileType == 'videoBook')
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.movie_creation_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            // 如果是游戏书，在右上角显示游戏图标
            if (entry.fileType == 'gameBook')
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sports_esports,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建没有封面时的占位符UI
  Widget _buildCoverPlaceholder(BookshelfEntry entry) {
    final colors = [
      Colors.deepPurple,
      Colors.teal,
      Colors.indigo,
      Colors.brown,
      Colors.blueGrey,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.blue,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.deepOrange,
      Colors.lightGreen,
      Colors.purple,
    ];
    final color = colors[entry.id.hashCode % colors.length];

    IconData icon = Icons.book_outlined;
    if (entry.fileType == 'gameBook') {
      icon = Icons.sports_esports;
    } else if (entry.fileType == 'videoBook') icon = Icons.movie_creation_outlined;

    return Container(
      color: color[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                entry.title,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
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