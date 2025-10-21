// lib/ui/reader/book_reader.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiktoken/tiktoken.dart';
import 'package:video_player/video_player.dart';
import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_executor/single_illustration_executor.dart';

class _ReaderTheme {
  final String id;
  final String name;
  final Color background;
  final Color font;

  const _ReaderTheme({required this.id, required this.name, required this.background, required this.font});

  static const List<_ReaderTheme> themes = [
    _ReaderTheme(id: 'default', name: '默认', background: Color(0xFFFFFFFF), font: Color(0xFF333333)),
    _ReaderTheme(id: 'eye_care', name: '护眼', background: Color(0xFFF0F5E9), font: Color(0xFF58452D)),
    _ReaderTheme(id: 'dark', name: '夜间', background: Color(0xFF222222), font: Color(0xFFBBBBBB)),
  ];
}

enum DisplayMode { original, translation }

class BookReaderPage extends StatefulWidget {
  final Book book;
  // [新增] 用于接收初始章节索引
  final int initialChapterIndex;

  const BookReaderPage({
    super.key,
    required this.book,
    this.initialChapterIndex = 0, // [新增] 设置默认值
  });

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  late Book _currentBook;
  bool _isTaskRunning = false;
  final _illustrationExecutor = SingleIllustrationExecutor.instance;
  final _videoExecutor = SingleVideoExecutor.instance; // 视频执行器实例
  final _textModificationExecutor = TextModificationExecutor.instance; // 文本修改执行器

  // --- 页面状态和设置 ---
  // [修改] PageController 需要在 initState 中初始化，以便使用 initialPage
  late PageController _pageController;
  late int _currentChapterIndex;

  // --- UI 可见性控制 ---
  final ValueNotifier<bool> _isToolbarVisible = ValueNotifier(true);

  // --- 阅读器设置 ---
  late _ReaderTheme _currentTheme;
  late double _fontSize;
  late double _lineHeight;
  late String _fontFamily;
  DisplayMode _displayMode = DisplayMode.original;

  // --- 配置服务实例和加载状态 ---
  final _configService = ConfigService();
  bool _settingsLoaded = false;


  @override
  void initState() {
    super.initState();
    _currentBook = widget.book;

    // [修改] 初始化章节索引和 PageController
    _currentChapterIndex = widget.initialChapterIndex;
    _pageController = PageController(initialPage: _currentChapterIndex);

    _loadReaderSettings();
    _toggleSystemUI(_isToolbarVisible.value);
  }

  // 从ConfigService加载阅读器设置
  void _loadReaderSettings() {
    final themeId = _configService.getSetting<String>('reader_theme_id', 'default');
    _currentTheme = _ReaderTheme.themes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => _ReaderTheme.themes.first,
    );
    _fontSize = _configService.getSetting<double>('reader_font_size', 18.0);
    _lineHeight = _configService.getSetting<double>('reader_line_height', 1.8);
    _fontFamily = _configService.getSetting<String>('reader_font_family', 'SystemDefault');

    setState(() {
      _settingsLoaded = true;
    });
  }

  // 切换系统UI（状态栏、导航栏）的可见性
  void _toggleSystemUI(bool show) {
    if (show) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  // 切换工具栏的显示和隐藏
  void _toggleToolbarVisibility() {
    _isToolbarVisible.value = !_isToolbarVisible.value;
    _toggleSystemUI(_isToolbarVisible.value);
  }

  // 刷新书籍状态
  Future<void> _refreshBookState() async {
    final updatedBook = await CacheManager().loadBookDetail(_currentBook.id);
    if (updatedBook != null && mounted) {
      setState(() {
        _currentBook = updatedBook;
      });
    }
  }

  // 通用任务处理逻辑，接收一个返回 Future 的函数
  Future<void> _handleGenericTask(Future<dynamic> Function() taskFunction, String processingMessage) async {
    if (_isTaskRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有任务在运行中,请稍候...')));
      return;
    }
    _isTaskRunning = true;
    final messenger = ScaffoldMessenger.of(context);

    // 使用更安全的定位方式
    final screenHeight = MediaQuery.of(context).size.height;
    final safeTopPadding = MediaQuery.of(context).padding.top;
    final toolbarHeight = kToolbarHeight;

    // 计算安全的底部边距，确保 SnackBar 不会超出屏幕
    final safeBottomMargin = screenHeight - toolbarHeight - safeTopPadding - 100;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 16),
            Expanded(child: Text(processingMessage, overflow: TextOverflow.ellipsis)),
          ],
        ),
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        // 使用更安全的边距计算
        margin: EdgeInsets.only(
          bottom: safeBottomMargin.clamp(80.0, screenHeight - 150), // 限制在安全范围内
          left: 20,
          right: 20
        ),
      ),
    );

    try {
      await taskFunction();
    } catch (e) {
      print("任务执行失败: $e");
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      messenger.hideCurrentSnackBar();
      _isTaskRunning = false;
    }
  }

  // 视频任务处理逻辑
  Future<void> _handleVideoTask(Future<void> Function() taskFunction) async {
    await _handleGenericTask(() async {
      await taskFunction();
      await CacheManager().saveBookDetail(_currentBook);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('视频生成成功！正在刷新...')));
        await _refreshBookState();
      }
    }, '正在生成视频...');
  }

  // 插图任务处理逻辑
  Future<void> _handleIllustrationTask(Future<void> Function() taskFunction) async {
    await _handleGenericTask(() async {
      await taskFunction();
      await CacheManager().saveBookDetail(_currentBook);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('插图生成成功！正在刷新...')));
        await _refreshBookState();
      }
    }, '正在生成插图...');
  }

  // 文本修改任务处理逻辑
  Future<void> _handleTextModificationTask(Future<Book?> Function() modificationFunction, String successMessage) async {
    await _handleGenericTask(() async {
      final updatedBook = await modificationFunction();
      if (updatedBook != null && mounted) {
        setState(() {
          _currentBook = updatedBook;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      } else if (mounted) {
        throw Exception("未能成功更新书籍内容。");
      }
    }, '正在处理文本...');
  }
  //  删除插图逻辑
  Future<void> _deleteIllustration(String imagePath, LineStructure line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这张图片吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final originalPaths = List<String>.from(line.illustrationPaths);
      line.illustrationPaths.remove(imagePath);
      setState(() {});
      try {
        await File(imagePath).delete();
        await CacheManager().saveBookDetail(_currentBook);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片已删除')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除文件失败: $e'), backgroundColor: Colors.red));
        }
        line.illustrationPaths.clear();
        line.illustrationPaths.addAll(originalPaths);
        setState(() {});
      }
    }
  }

  // 删除视频逻辑
  Future<void> _deleteVideo(String videoPath, LineStructure line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个视频吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final originalPaths = List<String>.from(line.videoPaths);
      line.videoPaths.remove(videoPath);
      setState(() {});
      try {
        await File(videoPath).delete();
        await CacheManager().saveBookDetail(_currentBook);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('视频已删除')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除文件失败: $e'), backgroundColor: Colors.red));
        }
        line.videoPaths.clear();
        line.videoPaths.addAll(originalPaths);
        setState(() {});
      }
    }
  }

  // 为选择文本生成插图
  Future<void> _generateIllustrationForSelection(String selectedText, LineStructure targetLine, ChapterStructure targetChapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');
    await _handleIllustrationTask(() =>
      _illustrationExecutor.generateIllustrationForSelection(
        book: _currentBook,
        chapter: targetChapter,
        targetLine: targetLine,
        selectedText: selectedText,
        imageSaveDir: illustrationsDir.path,
      ),
    );
  }

  // 删除划选文本
  Future<void> _performDelete(LineStructure firstLine, LineStructure lastLine, ChapterStructure chapter) async {
    await _handleTextModificationTask(() => CacheManager().updateTextInRange(
      bookId: _currentBook.id,
      chapterId: chapter.id,
      startLineId: firstLine.id,
      endLineId: lastLine.id,
      newContent: '', // 传入空字符串即为删除
    ), '文本已删除');
  }

  // 显示改写要求对话框
  Future<void> _showRewriteDialog(String selectedText, LineStructure firstLine, LineStructure lastLine, ChapterStructure chapter) async {
    if (_currentBook.fileType != 'txt') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('错误：非 TXT 格式的书籍不支持改写功能。'), backgroundColor: Colors.red),
      );
      return;
    }

    final requirementController = TextEditingController();
    final userRequirement = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改写文本'),
        content: TextField(
          controller: requirementController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '改写要求',
            hintText: '例如：写得更生动一些、缩短内容等',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(requirementController.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (userRequirement != null && userRequirement.trim().isNotEmpty) {
      await _performRewrite(userRequirement, selectedText, firstLine, lastLine, chapter);
    }
  }

  // 执行文本改写
  Future<void> _performRewrite(String requirement, String selectedText, LineStructure firstLine, LineStructure lastLine, ChapterStructure chapter) async {
    final context = _extractContextAroundSelection(firstLine, lastLine, chapter, 4000);

    await _handleTextModificationTask(() async {
      final rewrittenText = await _textModificationExecutor.rewriteText(
        precedingText: context.preceding,
        selectedText: selectedText,
        succeedingText: context.succeeding,
        userRequirement: requirement,
      );

      return CacheManager().updateTextInRange(
        bookId: _currentBook.id,
        chapterId: chapter.id,
        startLineId: firstLine.id,
        endLineId: lastLine.id,
        newContent: rewrittenText,
      );
    }, '文本改写成功');
  }

  // 提取划选文本前后的上下文
  ({String preceding, String succeeding}) _extractContextAroundSelection(LineStructure firstLine, LineStructure lastLine, ChapterStructure chapter, int maxTokens) {
    final encoding = encodingForModel("gpt-4");
    final lines = chapter.lines;
    final firstIndex = lines.indexOf(firstLine);
    final lastIndex = lines.indexOf(lastLine);
    if (firstIndex == -1 || lastIndex == -1) return (preceding: '', succeeding: '');

    // 提取上文
    List<String> precedingLines = [];
    int precedingTokens = 0;
    for (int i = firstIndex - 1; i >= 0; i--) {
      final lineText = lines[i].text;
      final lineTokens = encoding.encode(lineText).length;
      if (precedingTokens + lineTokens > maxTokens) break;
      precedingTokens += lineTokens;
      precedingLines.insert(0, lineText);
    }

    // 提取下文
    List<String> succeedingLines = [];
    int succeedingTokens = 0;
    for (int i = lastIndex + 1; i < lines.length; i++) {
      final lineText = lines[i].text;
      final lineTokens = encoding.encode(lineText).length;
      if (succeedingTokens + lineTokens > maxTokens) break;
      succeedingTokens += lineTokens;
      succeedingLines.add(lineText);
    }

    return (preceding: precedingLines.join('\n'), succeeding: succeedingLines.join('\n'));
  }


  // 重新生成插图
  Future<void> _regenerateIllustrationForLine(LineStructure line, ChapterStructure chapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');
    await _handleIllustrationTask(() =>
      _illustrationExecutor.regenerateIllustration(
        chapter: chapter,
        line: line,
        imageSaveDir: illustrationsDir.path,
      ),
    );
  }

  // 从图片生成视频的触发方法
  Future<void> _generateVideoFromImage(String imagePath, LineStructure line, ChapterStructure chapter) async {
    final videosDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'videos');
    await _handleVideoTask(() =>
      _videoExecutor.generateVideoFromImage(
        chapter: chapter,
        line: line,
        imagePath: imagePath,
        saveDir: videosDir.path,
      ),
    );
  }

  // 辅助函数，用于根据文本选择范围找到对应的起始和结束行
  ({ChapterStructure chapter, LineStructure firstLine, LineStructure lastLine})?
      _findLinesForSelection(
    TextSelection selection,
    List<({LineStructure line, ChapterStructure chapter})> linesInBlock,
  ) {
    int cumulativeLength = 0;
    LineStructure? firstLine;
    ChapterStructure? chapter;
    LineStructure? lastLine;

    for (final info in linesInBlock) {
      final line = info.line;
      String textToShow = (_displayMode == DisplayMode.translation &&
              line.translatedText?.isNotEmpty == true)
          ? line.translatedText!
          : line.text;
      // 注意：SelectableText.rich 会在每个 TextSpan 后面加一个换行符 \n
      int lineLength = (textToShow + '\n').length;

      // 检查划选的起点是否在本行内
      if (firstLine == null && selection.start < cumulativeLength + lineLength) {
        firstLine = line;
        chapter = info.chapter;
      }
      // 检查划选的终点是否在本行内
      if (selection.end <= cumulativeLength + lineLength) {
        lastLine = line;
        // 如果起点也在本行（或者之前的行），并且终点已找到，就可以确定范围了
        if (firstLine != null) break;
      }
      cumulativeLength += lineLength;
    }

    // 如果循环结束还没找到lastLine（比如划选到末尾），则将最后一行作为lastLine
    if (firstLine != null && lastLine == null && linesInBlock.isNotEmpty) {
      lastLine = linesInBlock.last.line;
    }

    if (chapter != null && firstLine != null && lastLine != null) {
      return (chapter: chapter, firstLine: firstLine, lastLine: lastLine);
    }
    return null;
  }

  // 创建一个自定义的上下文菜单项
  Widget _buildContextMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    // 使用 TextButton 来获得点击效果和正确的 Material 状态
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // 设置合适的内边距，拉开上下间距
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        // 设置形状，以便与菜单卡片融合
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4.0)),
        ),
        // 让按钮内容左对齐
        alignment: Alignment.centerLeft,
        // 确保前景色（文本和图标颜色）能适应主题
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      child: Row(
        // MainAxisSize.max 是 Row 的默认值，它会尝试占据所有可用宽度
        children: [
          Icon(icon, size: 22.0),
          const SizedBox(width: 16.0), // 图标和文本之间的间距
          // Expanded 确保文本部分在需要时可以换行，并且整个 Row 会占满宽度
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // 改进后的文本上下文菜单
  Widget _buildTextContextMenu(
      BuildContext context,
      EditableTextState state,
      List<({LineStructure line, ChapterStructure chapter})> linesInBlock,
      ) {
    final selection = state.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) {
      // 如果没有选择文本，显示默认的复制/粘贴等菜单
      return AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: state.contextMenuButtonItems,
        anchors: state.contextMenuAnchors,
      );
    }

    final selectedText = state.textEditingValue.text.substring(
      selection.start,
      selection.end,
    ).trim();

    final lineInfo = _findLinesForSelection(selection, linesInBlock);

    if (selectedText.isEmpty || lineInfo == null) {
      // 如果选择的文本为空或无法定位行，也显示默认菜单
      return AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: state.contextMenuButtonItems,
        anchors: state.contextMenuAnchors,
      );
    }

    return AdaptiveTextSelectionToolbar(
      anchors: state.contextMenuAnchors,
      children: [
        _buildContextMenuItem(
          context: context,
          icon: Icons.edit_note_outlined,
          label: 'AI改写文本',
          onPressed: () {
            state.hideToolbar(true);
            _showRewriteDialog(selectedText, lineInfo.firstLine, lineInfo.lastLine, lineInfo.chapter);
          },
        ),
        _buildContextMenuItem(
          context: context,
          icon: Icons.image_outlined,
          label: 'AI生成插图',
          onPressed: () {
            state.hideToolbar(true);
            _generateIllustrationForSelection(selectedText, lineInfo.lastLine, lineInfo.chapter);
          },
        ),
        _buildContextMenuItem(
          context: context,
          icon: Icons.delete_outline,
          label: '删除选取文本',
          onPressed: () {
            state.hideToolbar(true);
            _performDelete(lineInfo.firstLine, lineInfo.lastLine, lineInfo.chapter);
          },
        ),
      ],
    );
  }

  /// 显示章节重写要求对话框
  Future<void> _showRewriteChapterDialog() async {
    // 1. 检查书籍类型
    if (_currentBook.fileType != 'txt') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只有 TXT 格式的书籍才支持整章重写。'), backgroundColor: Colors.orange),
      );
      return;
    }

    final requirementController = TextEditingController();
    final userRequirement = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重写本章'),
        content: TextField(
          controller: requirementController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '重写要求',
            hintText: '例如：增加更多心理描写，让节奏更紧张...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(requirementController.text),
            child: const Text('开始重写'),
          ),
        ],
      ),
    );

    if (userRequirement != null && userRequirement.trim().isNotEmpty) {
      await _performChapterRewrite(userRequirement);
    }
  }

  /// 执行章节重写
  Future<void> _performChapterRewrite(String requirement) async {
    final currentChapter = _currentBook.chapters[_currentChapterIndex];
    final originalContent = currentChapter.lines.map((l) => l.text).join('\n');

    await _handleGenericTask(() async {
      // 调用执行器完成AI重写
      final result = await _textModificationExecutor.rewriteChapter(
        originalContent: originalContent,
        userRequirement: requirement,
      );

      // 使用新的缓存管理器方法更新数据
      final updatedBook = await CacheManager().updateChapterContent(
        bookId: _currentBook.id,
        chapterId: currentChapter.id,
        newTitle: result.newTitle,
        newContent: result.newContent,
      );

      if (updatedBook != null && mounted) {
        setState(() {
          _currentBook = updatedBook;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('章节重写成功！')));
      } else {
        throw Exception("未能成功更新书籍内容。");
      }
    }, '正在重写章节，可能需要几分钟...');
  }

  // [新增] 保存阅读进度的方法
  Future<void> _saveReadingProgress(int chapterIndex) async {
    // 使用一个独立的 CacheManager 实例来执行后台保存
    final cacheManager = CacheManager();
    final entries = await cacheManager.loadBookshelf();
    final entryIndex = entries.indexWhere((e) => e.id == _currentBook.id);

    if (entryIndex != -1) {
      final currentEntry = entries[entryIndex];
      // 只有在章节索引发生变化时才执行保存，避免不必要的磁盘写入
      if (currentEntry.lastReadChapterIndex != chapterIndex) {
        entries[entryIndex] = currentEntry.copyWith(lastReadChapterIndex: chapterIndex);
        await cacheManager.saveBookshelf(entries);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _isToolbarVisible.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // 显示设置面板
  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _ReaderSettingsPanel(
          initialTheme: _currentTheme,
          initialFontSize: _fontSize,
          initialLineHeight: _lineHeight,
          initialFontFamily: _fontFamily,
          initialDisplayMode: _displayMode,
          onSettingsChanged: (theme, fontSize, fontFamily, displayMode, lineHeight) {
            setState(() {
              _currentTheme = theme;
              _fontSize = fontSize;
              _fontFamily = fontFamily;
              _displayMode = displayMode;
              _lineHeight = lineHeight;
            });
            _configService.modifySetting('reader_theme_id', theme.id);
            _configService.modifySetting('reader_font_size', fontSize);
            _configService.modifySetting('reader_line_height', lineHeight);
            _configService.modifySetting('reader_font_family', fontFamily);
          },
        );
      },
    );
  }

  // 跳转到指定章节
  void _jumpToChapter(int chapterIndex) {
      _pageController.jumpToPage(chapterIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _currentTheme.background,
      body: ValueListenableBuilder<bool>(
        valueListenable: _isToolbarVisible,
        builder: (context, isVisible, child) {
          return Stack(
            children: [
              child!,
              _buildTopToolbar(isVisible),
            ],
          );
        },
        child: GestureDetector(
          onTap: _toggleToolbarVisibility,
          child: SafeArea(
            top: false,
            bottom: false,
            child: _buildReaderBody(),
          ),
        ),
      ),
      endDrawer: Drawer(
        // 使用 Center 组件将列表垂直居中
        child: Center(
          child: ListView.builder(
            // 让 ListView 的高度包裹其内容，这是居中的关键
            shrinkWrap: true,
            // 为列表添加一些垂直内边距，避免内容紧贴边缘
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            itemCount: _currentBook.chapters.length,
            itemBuilder: (context, index) {
              final chapter = _currentBook.chapters[index];
              return ListTile(
                title: Text(
                  chapter.title,
                  // 将每个章节标题的文本也居中显示
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: _currentChapterIndex == index ? FontWeight.bold : FontWeight.normal,
                    color: _currentChapterIndex == index ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _jumpToChapter(index);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // 构建顶部工具栏
  Widget _buildTopToolbar(bool isVisible) {
    final chapterTitle = _currentBook.chapters.isNotEmpty
        ? _currentBook.chapters[_currentChapterIndex].title
        : "无章节";
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: isVisible ? 0 : -kToolbarHeight - MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.8),
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          child: SizedBox(
            height: kToolbarHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Center(
                  child: Padding(
                    // 调整内边距以适应右侧更多的按钮
                    padding: const EdgeInsets.only(left: 56, right: 144),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: '上一章',
                          onPressed: _currentChapterIndex > 0 ? () => _jumpToChapter(_currentChapterIndex - 1) : null,
                        ),
                        Flexible(
                          child: Text(
                            chapterTitle,
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: '下一章',
                          onPressed: _currentChapterIndex < _currentBook.chapters.length - 1 ? () => _jumpToChapter(_currentChapterIndex + 1) : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ✨ MODIFICATION: 交换了 "目录" 和 "重写本章" 按钮的位置
                      Builder(builder: (context) {
                        return IconButton(
                          icon: const Icon(Icons.menu_book_outlined),
                          tooltip: '目录',
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                        );
                      }),
                      IconButton(
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        tooltip: 'AI重写本章',
                        onPressed: _showRewriteChapterDialog,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: '阅读设置',
                        onPressed: _showReaderSettings,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建阅读器主体
  Widget _buildReaderBody() {
    if (_currentBook.chapters.isEmpty) {
      return Center(child: Text('书籍内容为空', style: TextStyle(color: _currentTheme.font)));
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _currentBook.chapters.length,
      onPageChanged: (index) {
        setState(() {
          _currentChapterIndex = index;
        });
        // [修改] 当页面改变时，调用保存进度的方法
        _saveReadingProgress(index);
      },
      itemBuilder: (context, chapterIndex) {
        return SingleChildScrollView(
          // 仅在 Android 上应用页面滚动效果
          physics: Platform.isAndroid ? const PageScrollPhysics() : null,
          child: _buildChapterContent(chapterIndex),
        );
      },
    );
  }

  // 构建章节内容
  Widget _buildChapterContent(int chapterIndex) {
    final chapter = _currentBook.chapters[chapterIndex];

    return Padding(
      padding: EdgeInsets.fromLTRB(24.0, 48.0 + MediaQuery.of(context).padding.top, 24.0, 48.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: Text(
              chapter.title,
              style: TextStyle(
                fontSize: _fontSize * 1.5,
                fontWeight: FontWeight.bold,
                color: _currentTheme.font,
                fontFamily: _fontFamily == 'SystemDefault' ? null : _fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          ..._buildContentWidgets(chapter),
        ],
      ),
    );
  }

  List<Widget> _buildContentWidgets(ChapterStructure chapter) {
    List<Widget> contentWidgets = [];
    List<({LineStructure line, ChapterStructure chapter})> currentTextLines = [];

    void submitTextBlock() {
      if (currentTextLines.isNotEmpty) {
        contentWidgets.add(
            _buildSelectableTextBlock(List.from(currentTextLines))
        );
        currentTextLines.clear();
      }
    }

    for (final line in chapter.lines) {
      if (line.text.trim().isNotEmpty) {
        currentTextLines.add((line: line, chapter: chapter));
      }

      if (line.illustrationPaths.isNotEmpty || line.videoPaths.isNotEmpty) {
        submitTextBlock();
        contentWidgets.add(
          _IllustrationGallery(
            imagePaths: line.illustrationPaths,
            videoPaths: line.videoPaths,
            onRegenerate: () => _regenerateIllustrationForLine(line, chapter),
            onDeleteImage: (path) => _deleteIllustration(path, line),
            onDeleteVideo: (path) => _deleteVideo(path, line),
            onGenerateVideo: (path) => _generateVideoFromImage(path, line, chapter),
          ),
        );
      }
    }

    submitTextBlock();
    return contentWidgets;
  }

  Widget _buildSelectableTextBlock(List<({LineStructure line, ChapterStructure chapter})> linesInfo) {
    return SelectableText.rich(
      TextSpan(
        children: linesInfo.map((info) {
          final line = info.line;
          String textToShow;
          if (_displayMode == DisplayMode.translation && line.translatedText != null && line.translatedText!.isNotEmpty) {
            textToShow = line.translatedText!;
          } else {
            textToShow = line.text;
          }
          return TextSpan(text: '$textToShow\n');
        }).toList(),
      ),
      style: TextStyle(
        fontSize: _fontSize,
        height: _lineHeight,
        color: _currentTheme.font,
        fontFamily: _fontFamily == 'SystemDefault' ? null : _fontFamily,
      ),
      textAlign: TextAlign.justify,
      contextMenuBuilder: (context, state) => _buildTextContextMenu(context, state, linesInfo),
    );
  }
}


// 设置面板
class _ReaderSettingsPanel extends StatefulWidget {

  final _ReaderTheme initialTheme;
  final double initialFontSize;
  final double initialLineHeight;
  final String initialFontFamily;
  final DisplayMode initialDisplayMode;
  final Function(
    _ReaderTheme theme,
    double fontSize,
    String fontFamily,
    DisplayMode displayMode,
    double lineHeight,
  ) onSettingsChanged;

  const _ReaderSettingsPanel({
    required this.initialTheme,
    required this.initialFontSize,
    required this.initialLineHeight,
    required this.initialFontFamily,
    required this.initialDisplayMode,
    required this.onSettingsChanged,
  });

  @override
  State<_ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<_ReaderSettingsPanel> {
  late _ReaderTheme _currentTheme;
  late double _fontSize;
  late double _lineHeight;
  late String _fontFamily;
  late DisplayMode _displayMode;

  @override
  void initState() {
    super.initState();
    _currentTheme = widget.initialTheme;
    _fontSize = widget.initialFontSize;
    _lineHeight = widget.initialLineHeight;
    _fontFamily = widget.initialFontFamily;
    _displayMode = widget.initialDisplayMode;
  }

  void _notifyParent() {
    widget.onSettingsChanged(_currentTheme, _fontSize, _fontFamily, _displayMode, _lineHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12.0,
        left: 8.0,
        right: 8.0,
        bottom: MediaQuery.of(context).viewPadding.bottom + 16.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSectionTitle(context, '背景主题'),
                  _buildThemeSelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, '字体设置'),
                  _buildFontSizeControl(),
                  const SizedBox(height: 16),
                  _buildLineHeightControl(),
                  const SizedBox(height: 16),
                  _buildFontFamilySelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, '内容显示'),
                  _buildDisplayModeControl(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0, top: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _ReaderTheme.themes.map((theme) {
          return _ThemeChip(
            theme: theme,
            isSelected: _currentTheme.id == theme.id,
            onSelect: () {
              setState(() => _currentTheme = theme);
              _notifyParent();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFontSizeControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Text("Aa", style: TextStyle(fontSize: 16, color: Colors.grey)),
          Expanded(
            child: Slider(
              value: _fontSize,
              min: 12.0, max: 32.0, divisions: 20,
              label: _fontSize.round().toString(),
              onChanged: (value) {
                setState(() => _fontSize = value);
                _notifyParent();
              },
            ),
          ),
          const Text("Aa", style: TextStyle(fontSize: 24, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLineHeightControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Icon(Icons.format_line_spacing),
          Expanded(
            child: Slider(
              value: _lineHeight,
              min: 1.2, max: 2.5, divisions: 13,
              label: _lineHeight.toStringAsFixed(1),
              onChanged: (value) {
                setState(() => _lineHeight = value);
                _notifyParent();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontFamilySelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: DropdownButtonFormField<String>(
        value: _fontFamily,
        decoration: InputDecoration(
          labelText: '选用字体',
          prefixIcon: const Icon(Icons.font_download_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
        items: const [
          DropdownMenuItem(value: 'SystemDefault', child: Text('系统默认')),
          DropdownMenuItem(value: 'SongTi', child: Text('宋体 (需配置)')),
          DropdownMenuItem(value: 'KaiTi', child: Text('楷体 (需配置)')),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _fontFamily = value);
            _notifyParent();
          }
        },
      ),
    );
  }

  Widget _buildDisplayModeControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<DisplayMode>(
          segments: const [
            ButtonSegment(value: DisplayMode.original, label: Text('原文'), icon: Icon(Icons.menu_book)),
            ButtonSegment(value: DisplayMode.translation, label: Text('译文'), icon: Icon(Icons.translate)),
          ],
          selected: {_displayMode},
          onSelectionChanged: (newSelection) {
            setState(() => _displayMode = newSelection.first);
            _notifyParent();
          },
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final _ReaderTheme theme;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ThemeChip({required this.theme, required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: theme.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.primary : theme.font.withOpacity(0.5),
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: isSelected
                ? Icon(Icons.check, color: theme.font, size: 24)
                : Center(child: Text('A', style: TextStyle(color: theme.font, fontSize: 20, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 8),
          Text(
            theme.name,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// 插图/视频画廊组件
class _IllustrationGallery extends StatelessWidget {
  final List<String> imagePaths;
  final List<String> videoPaths;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onDeleteImage;
  final ValueChanged<String> onDeleteVideo;
  final ValueChanged<String> onGenerateVideo;

  const _IllustrationGallery({
    required this.imagePaths,
    required this.videoPaths,
    required this.onRegenerate,
    required this.onDeleteImage,
    required this.onDeleteVideo,
    required this.onGenerateVideo,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty && videoPaths.isEmpty) return const SizedBox.shrink();

    final imageTiles = imagePaths.map((path) {
      return _ImageTile(
        key: ValueKey(path),
        imagePath: path,
        onRegenerate: onRegenerate,
        onDelete: () => onDeleteImage(path),
        onGenerateVideo: () => onGenerateVideo(path),
      );
    }).toList();

    final videoTiles = videoPaths.map((path) {
      return _VideoTile(
        key: ValueKey(path),
        videoPath: path,
        onDelete: () => onDeleteVideo(path),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 16.0,
        alignment: WrapAlignment.center,
        children: [...imageTiles, ...videoTiles],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;
  final VoidCallback onGenerateVideo;

  const _ImageTile({
    super.key,
    required this.imagePath,
    required this.onRegenerate,
    required this.onDelete,
    required this.onGenerateVideo,
  });

  void _showEnlargedImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // 这个外层的 GestureDetector 负责处理点击空白区域返回
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: InteractiveViewer(
                    clipBehavior: Clip.none,
                    child: Image.file(File(imagePath)),
                  ),
                ),
                const SizedBox(height: 16),
                // 这个 GestureDetector 是有用的，它防止点击按钮区域时关闭弹窗
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    // ✨ MODIFICATION START: 将 IconButton 替换为带文本的 _ViewerButton
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewerButton(
                          icon: Icons.refresh,
                          label: '重新生成',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRegenerate();
                          },
                        ),
                        const SizedBox(width: 16),
                        _ViewerButton(
                          icon: Icons.movie_creation_outlined,
                          label: '图生视频',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onGenerateVideo();
                          },
                        ),
                        const SizedBox(width: 16),
                        _ViewerButton(
                          icon: Icons.delete_outline,
                          label: '删除',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onDelete();
                          },
                        ),
                      ],
                    ),
                    // ✨ MODIFICATION END
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40)),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showEnlargedImage(context),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Image.file(
            imageFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatefulWidget {
  final String videoPath;
  final VoidCallback onDelete;

  const _VideoTile({
    super.key,
    required this.videoPath,
    required this.onDelete,
  });

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    final file = File(widget.videoPath);
    if (file.existsSync()) {
      _controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
              _controller.setVolume(0);
              _controller.setLooping(true);
            });
          }
        }).catchError((error) { // 添加错误处理
            print("视频初始化失败: $error");
            if (mounted) {
              setState(() {
                _isInitialized = false;
              });
            }
        });
    } else {
      _isInitialized = false;
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _showEnlargedVideo(BuildContext context) async {
    if (!_isInitialized) return;

    // 暂停预览
    _controller.pause();

    // 等待Dialog关闭
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        // 传递已有的控制器
        return _VideoPlayerDialog(
          controller: _controller,
          onDelete: widget.onDelete,
        );
      },
    );

    // Dialog关闭后，恢复预览状态
    if (mounted) {
      _controller.setVolume(0);
      _controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: Icon(Icons.movie, color: Colors.grey, size: 40)),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showEnlargedVideo(context),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16/9,
                child: VideoPlayer(_controller),
              ),
              MouseRegion(
                onEnter: (_) {
                  if(_isInitialized) _controller.play();
                },
                onExit: (_) {
                  if(_isInitialized) _controller.pause();
                },
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Icon(Icons.play_circle_outline, color: Colors.white.withOpacity(0.7), size: 50),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onDelete;

  const _VideoPlayerDialog({required this.controller, required this.onDelete});

  @override
  _VideoPlayerDialogState createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // 使用传入的 controller
    // 确保视频从头开始播放，并且有声音
    widget.controller.seekTo(Duration.zero);
    widget.controller.setVolume(1.0);
    widget.controller.setLooping(true);
    widget.controller.play();
    _isPlaying = true;
    // 添加监听器以响应播放状态变化
    widget.controller.addListener(_videoListener);
  }

  void _videoListener() {
    if (mounted && _isPlaying != widget.controller.value.isPlaying) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    // Dialog 不负责 dispose 控制器
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
        _isPlaying = false;
      } else {
        widget.controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: _togglePlayPause, // 点击视频区域切换播放/暂停
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(widget.controller),
                        if (!_isPlaying)
                          Icon(
                            Icons.play_arrow,
                            color: Colors.white.withOpacity(0.8),
                            size: 80,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: _ViewerButton(
                  icon: Icons.delete_outline,
                  label: '删除视频',
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ViewerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // 使用 InkWell 来提供点击时的水波纹效果
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // 为按钮提供一些内边距，使其更易于点击
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4), // 图标和文本之间的间距
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}