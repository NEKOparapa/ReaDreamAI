// lib/ui/reader/book_reader.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiktoken/tiktoken.dart';

import '../../base/config_service.dart';
import '../../models/book.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_executor/single_illustration_executor.dart';
import 'widgets/illustration_gallery.dart';
import 'widgets/reader_settings_panel.dart';


class BookReaderPage extends StatefulWidget {
  final Book book;
  final int initialChapterIndex;

  const BookReaderPage({
    super.key,
    required this.book,
    this.initialChapterIndex = 0,
  });

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  late Book _currentBook;
  bool _isTaskRunning = false;
  final _illustrationExecutor = SingleIllustrationExecutor.instance;
  final _videoExecutor = SingleVideoExecutor.instance;
  final _textModificationExecutor = TextModificationExecutor.instance;

  // --- 页面状态和设置 ---
  late PageController _pageController;
  late int _currentChapterIndex;

  // --- UI 可见性控制 ---
  final ValueNotifier<bool> _isToolbarVisible = ValueNotifier(true);

  // --- 阅读器设置 ---
  // 使用从新文件导入的公开类
  late ReaderTheme _currentTheme;
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

    _currentChapterIndex = widget.initialChapterIndex;
    _pageController = PageController(initialPage: _currentChapterIndex);

    _loadReaderSettings();
    _toggleSystemUI(_isToolbarVisible.value);
  }

  // 从ConfigService加载阅读器设置
  void _loadReaderSettings() {
    final themeId = _configService.getSetting<String>('reader_theme_id', 'default');
    //使用公开的 ReaderTheme
    _currentTheme = ReaderTheme.themes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => ReaderTheme.themes.first,
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

    final screenHeight = MediaQuery.of(context).size.height;
    final safeTopPadding = MediaQuery.of(context).padding.top;
    final toolbarHeight = kToolbarHeight;

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
        margin: EdgeInsets.only(
          bottom: safeBottomMargin.clamp(80.0, screenHeight - 150),
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

  // 删除插图逻辑
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
      newContent: '',
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

    List<String> precedingLines = [];
    int precedingTokens = 0;
    for (int i = firstIndex - 1; i >= 0; i--) {
      final lineText = lines[i].text;
      final lineTokens = encoding.encode(lineText).length;
      if (precedingTokens + lineTokens > maxTokens) break;
      precedingTokens += lineTokens;
      precedingLines.insert(0, lineText);
    }

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
      int lineLength = (textToShow + '\n').length;

      if (firstLine == null && selection.start < cumulativeLength + lineLength) {
        firstLine = line;
        chapter = info.chapter;
      }
      if (selection.end <= cumulativeLength + lineLength) {
        lastLine = line;
        if (firstLine != null) break;
      }
      cumulativeLength += lineLength;
    }

    if (firstLine != null && lastLine == null && linesInBlock.isNotEmpty) {
      lastLine = linesInBlock.last.line;
    }

    if (chapter != null && firstLine != null && lastLine != null) {
      return (chapter: chapter, firstLine: firstLine, lastLine: lastLine);
    }
    return null;
  }

  // 改进后的文本上下文菜单
  Widget _buildTextContextMenu(
    BuildContext context,
    EditableTextState state,
    List<({LineStructure line, ChapterStructure chapter})> linesInBlock,
  ) {
    final selection = state.textEditingValue.selection;
    final selectedText = state.textEditingValue.text.substring(
      selection.start,
      selection.end,
    ).trim();

    final List<ContextMenuButtonItem> buttonItems = state.contextMenuButtonItems;

    if (selectedText.isNotEmpty) {
      final lineInfo = _findLinesForSelection(selection, linesInBlock);
      if (lineInfo != null) {
        final List<ContextMenuButtonItem> customItems = [
          ContextMenuButtonItem(
            label: 'AI生成插图',
            onPressed: () {
              ContextMenuController.removeAny();
              _generateIllustrationForSelection(selectedText, lineInfo.lastLine, lineInfo.chapter);
            },
          ),
          ContextMenuButtonItem(
            label: 'AI改写文本',
            onPressed: () {
              ContextMenuController.removeAny();
              _showRewriteDialog(selectedText, lineInfo.firstLine, lineInfo.lastLine, lineInfo.chapter);
            },
          ),
          ContextMenuButtonItem(
            label: '删除选中文本',
            onPressed: () {
              ContextMenuController.removeAny();
              _performDelete(lineInfo.firstLine, lineInfo.lastLine, lineInfo.chapter);
            },
          ),
        ];

        buttonItems.insertAll(0, customItems);
      }
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  /// 显示章节重写要求对话框
  Future<void> _showRewriteChapterDialog() async {
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
      final result = await _textModificationExecutor.rewriteChapter(
        originalContent: originalContent,
        userRequirement: requirement,
      );

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

  // 保存阅读进度的方法
  Future<void> _saveReadingProgress(int chapterIndex) async {
    final cacheManager = CacheManager();
    final entries = await cacheManager.loadBookshelf();
    final entryIndex = entries.indexWhere((e) => e.id == _currentBook.id);

    if (entryIndex != -1) {
      final currentEntry = entries[entryIndex];
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
        // 调用拆分后的组件
        return ReaderSettingsPanel(
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
            child: _buildReaderBody(),
          ),
        ),
      ),
      endDrawer: Drawer(
        child: Center(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            itemCount: _currentBook.chapters.length,
            itemBuilder: (context, index) {
              final chapter = _currentBook.chapters[index];
              return ListTile(
                title: Text(
                  chapter.title,
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
        _saveReadingProgress(index);
      },
      itemBuilder: (context, chapterIndex) {
        return SingleChildScrollView(
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
      padding: EdgeInsets.fromLTRB(24.0, 48.0, 24.0, 48.0),
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
          // [修改] 调用拆分后的组件
          IllustrationGallery(
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