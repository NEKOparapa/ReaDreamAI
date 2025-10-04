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
import '../reader/book_reader.dart';
import '../../services/task_manager/task_manager_service.dart';
import '../../services/epub_exporter/epub_exporter.dart';
import '../../base/log/log_service.dart';
import 'generate_illustration_dialog.dart';
import 'generate_translation_dialog.dart';
import 'generate_video_dialog.dart';

/// 书架页面 StatefulWidget
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

/// 书架页面的状态管理类
class _BookshelfPageState extends State<BookshelfPage> {
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
    // 页面初始化时加载书架数据
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

    // 显示一个顶部的处理中提示条
    final controller = _showTopMessage('正在处理文件...',
        leading: const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        duration: const Duration(minutes: 5)); // 持续时间设为5分钟，处理完后会手动关闭

    int newBookCount = 0;
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

    controller.close(); // 关闭顶部的处理中提示条
    setState(() => _isProcessing = false);

    // 如果组件挂载且有新书添加，显示成功提示
    if (mounted && newBookCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功添加 $newBookCount 本书')),
      );
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
        title = content.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '无标题文本').trim();
        if (title.length > 40) {
          title = title.substring(0, 40);
        }
      }

      // 清理文件名中的非法字符
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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
        orElse: () => entry, // 如果找不到，使用旧条目作为备用
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
      barrierDismissible: false, // 阻止点击外部关闭
      builder: (context) => GenerateTranslationDialog(entry: entry),
    );

    // 如果对话框返回true，说明任务已成功创建
    if (taskCreated == true && mounted) {
      // 重新从缓存加载书架数据，以更新UI状态（例如显示"排队中"）
      await _loadBookshelf();

      // 找到更新后的条目，以获取正确的任务信息用于提示
      final updatedEntry = _entries.firstWhere(
        (e) => e.id == entry.id,
        orElse: () => entry, // 如果找不到，使用旧条目作为备用
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已为《${updatedEntry.title}》创建 ${updatedEntry.translationTaskChunks.length} 个翻译子任务'),
        ),
      );
    }
  }

  /// 为指定书籍生成视频任务
  Future<void> _generateVideosFromImages(BookshelfEntry entry) async {
    // 显示配置对话框，并等待其返回结果
    final bool? taskCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenerateVideoDialog(entry: entry),
    );

    // 如果对话框返回true，说明任务已成功创建
    if (taskCreated == true && mounted) {
      // 重新从缓存加载书架数据，以更新UI状态
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

  /// 删除书籍
  void _deleteBook(BookshelfEntry entry) async {
    final bookTitle = entry.title;
    // 从任务管理器中删除相关任务
    TaskManagerService.instance.deleteTask(entry.id);
    // 从UI中移除
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
    // 从缓存中删除书籍文件
    await CacheManager().removeBookCacheFolder(entry.id);
    // 保存书架变更
    await _saveBookshelf();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('《$bookTitle》已删除')),
      );
    }
  }

  /// 打开书籍阅读器页面
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

  /// 显示书籍条目的上下文菜单（右键菜单）
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
          // 仅在任务未开始、失败或取消时可点击
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
          // 始终启用此菜单项，让对话框来处理后续逻辑
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
          child: const Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('删除书籍')
            ],
          ),
        ),
      ],
    );
  }

  /// 导出书籍为 EPUB 格式
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
    } catch (e, s) {
      _showTopMessage('导出失败：$e', isError: true);
      LogService.instance.error('书籍导出失败', e, s);
    }
  }

  /// 在屏幕顶部显示一个消息条 (SnackBar)
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
      // 使用 DropTarget 包装以接收拖拽文件
      body: DropTarget(
        onDragDone: _onDragDone,
        onDragEntered: (details) => setState(() => _isDragging = true),
        onDragExited: (details) => setState(() => _isDragging = false),
        child: Container(
          // 根据是否拖拽中显示不同的边框和背景
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
          // 如果书架为空且不在加载中，则显示空状态，否则显示书籍网格
          child: _entries.isEmpty && !_isLoadingFromCache
              ? _buildEmptyState()
              : _buildBookshelfGrid(),
        ),
      ),
      // 浮动操作按钮
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _addBooksWithPicker,
            tooltip: '导入文件',
            heroTag: 'import_file', // heroTag 必须唯一
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

  /// 构建书架为空时的占位UI
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

  /// 构建书架网格视图
  Widget _buildBookshelfGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180, // 每个格子的最大宽度
        childAspectRatio: 2 / 3.2, // 宽高比
        crossAxisSpacing: 20, // 水平间距
        mainAxisSpacing: 20, // 垂直间距
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
    // 检查封面图片是否存在
    final hasCover =
        entry.coverImagePath != null && File(entry.coverImagePath!).existsSync();

    return GestureDetector(
      onTap: () => _openBook(entry), // 左键单击打开书籍
      onSecondaryTapDown: (details) => _showContextMenu(context, entry, details), // 右键单击显示菜单
      child: Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias, // 裁剪子组件以匹配圆角
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面区域
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
            // 标题区域
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

  /// 构建没有封面时的占位符UI
  Widget _buildCoverPlaceholder(BookshelfEntry entry) {
    // 根据书籍ID的哈希值选择一个颜色，确保同一本书的占位符颜色总是固定的
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