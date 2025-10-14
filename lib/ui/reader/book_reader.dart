// lib/ui/reader/book_reader.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const BookReaderPage({super.key, required this.book});

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  late Book _currentBook;
  bool _isTaskRunning = false;
  final _executor = SingleIllustrationExecutor.instance;
  final _videoExecutor = SingleVideoExecutor.instance; // 视频执行器实例

  // --- 页面状态和设置 ---
  final PageController _pageController = PageController();
  int _currentChapterIndex = 0;

  // --- UI 可见性控制 ---
  final ValueNotifier<bool> _isToolbarVisible = ValueNotifier(true);

  // --- 阅读器设置 ---
  late _ReaderTheme _currentTheme;
  late double _fontSize;
  late double _lineHeight;
  late String _fontFamily;
  DisplayMode _displayMode = DisplayMode.original; // 显示模式保持会话级状态

  // --- 配置服务实例和加载状态 ---
  final _configService = ConfigService();
  bool _settingsLoaded = false;


  @override
  void initState() {
    super.initState();
    _currentBook = widget.book;
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

  // 插图任务处理逻辑
  Future<void> _handleIllustrationTask(Future<void> taskFunction) async {
    if (_isTaskRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有任务在生成中，请稍候...')));
      return;
    }

    _isTaskRunning = true;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 16),
            Text('正在生成插图...'),
          ],
        ),
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 120, left: 20, right: 20),
      ),
    );

    try {
      await taskFunction;
      await CacheManager().saveBookDetail(_currentBook);
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('插图生成成功！正在刷新...')));
        await _refreshBookState();
      }
    } catch (e) {
      print("生成插图失败: $e");
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      _isTaskRunning = false;
    }
  }

  // 视频任务处理逻辑
  Future<void> _handleVideoTask(Future<void> taskFunction) async {
    if (_isTaskRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有任务在生成中，请稍候...')));
      return;
    }
    _isTaskRunning = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 16),
            Text('正在生成视频...'),
          ],
        ),
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 120, left: 20, right: 20),
      ),
    );
    try {
      await taskFunction;
      await CacheManager().saveBookDetail(_currentBook);
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('视频生成成功！正在刷新...')));
        await _refreshBookState();
      }
    } catch (e) {
      print("生成视频失败: $e");
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      _isTaskRunning = false;
    }
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
    await _handleIllustrationTask(
      _executor.generateIllustrationForSelection(
        book: _currentBook,
        chapter: targetChapter,
        targetLine: targetLine,
        selectedText: selectedText,
        imageSaveDir: illustrationsDir.path,
      ),
    );
  }

  // 重新生成插图
  Future<void> _regenerateIllustrationForLine(LineStructure line, ChapterStructure chapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');
    await _handleIllustrationTask(
      _executor.regenerateIllustration(
        chapter: chapter,
        line: line,
        imageSaveDir: illustrationsDir.path,
      ),
    );
  }

  // 从图片生成视频的触发方法
  Future<void> _generateVideoFromImage(String imagePath, LineStructure line, ChapterStructure chapter) async {
    final videosDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'videos');
    await _handleVideoTask(
      _videoExecutor.generateVideoFromImage(
        chapter: chapter,
        line: line,
        imagePath: imagePath,
        saveDir: videosDir.path,
      ),
    );
  }

  //文本上下文菜单
  Widget _buildTextContextMenu(
      BuildContext context,
      EditableTextState state,
      List<({LineStructure line, ChapterStructure chapter})> linesInBlock,
      ) {
    final selection = state.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: state.contextMenuButtonItems,
        anchors: state.contextMenuAnchors,
      );
    }

    final selectedText = state.textEditingValue.text.substring(
      selection.start,
      selection.end,
    ).trim();

    if (selectedText.isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: state.contextMenuButtonItems,
        anchors: state.contextMenuAnchors,
      );
    }
    
    LineStructure? targetLine;
    ChapterStructure? targetChapter;
    int cumulativeLength = 0;
    for (final info in linesInBlock) {
      final line = info.line;
      String textToShow;
      if (_displayMode == DisplayMode.translation && line.translatedText != null && line.translatedText!.isNotEmpty) {
        textToShow = line.translatedText!;
      } else {
        textToShow = line.text;
      }
      cumulativeLength += (textToShow + '\n\n').length;
      
      if (selection.end <= cumulativeLength) {
        targetLine = line;
        targetChapter = info.chapter;
        break;
      }
    }

    if (targetLine == null) {
      final lastInfo = linesInBlock.last;
      targetLine = lastInfo.line;
      targetChapter = lastInfo.chapter;
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: [
        ...state.contextMenuButtonItems,
        ContextMenuButtonItem(
          onPressed: () {
            state.hideToolbar();
            state.userUpdateTextEditingValue(
              state.textEditingValue.copyWith(
                selection: TextSelection.collapsed(offset: selection.extentOffset),
              ),
              SelectionChangedCause.toolbar,
            );
            if (targetLine != null && targetChapter != null) {
              _generateIllustrationForSelection(selectedText, targetLine, targetChapter);
            }
          },
          label: '为此处生成插图',
        ),
      ],
      anchors: state.contextMenuAnchors,
    );
  }


  @override
  void dispose() {
    _pageController.dispose();
    _isToolbarVisible.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // 显示设置面板，并使用英文id持久化
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
            // 1. 更新UI状态
            setState(() {
              _currentTheme = theme;
              _fontSize = fontSize;
              _fontFamily = fontFamily;
              _displayMode = displayMode;
              _lineHeight = lineHeight;
            });
            // 2. 持久化保存设置
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
        child: ListView.builder(
          itemCount: _currentBook.chapters.length,
          itemBuilder: (context, index) {
            final chapter = _currentBook.chapters[index];
            return ListTile(
              title: Text(chapter.title, style: TextStyle(
                fontWeight: _currentChapterIndex == index ? FontWeight.bold : FontWeight.normal,
                color: _currentChapterIndex == index ? Theme.of(context).colorScheme.primary : null,
              )),
              onTap: () {
                Navigator.pop(context);
                _jumpToChapter(index);
              },
            );
          },
        ),
      ),
    );
  }

  // 构建顶部工具栏 (AppBar)
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
                    padding: const EdgeInsets.only(left: 56, right: 96),
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

  // 构建阅读器主体内容
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
      },
      itemBuilder: (context, chapterIndex) {
        return SingleChildScrollView(
          child: _buildChapterContent(chapterIndex),
        );
      },
    );
  }

  // 构建章节内容 Widget
  Widget _buildChapterContent(int chapterIndex) {
    final chapter = _currentBook.chapters[chapterIndex];
    
    return Padding(
      padding: EdgeInsets.fromLTRB(24.0, 48.0 + kToolbarHeight + MediaQuery.of(context).padding.top, 24.0, 48.0 + MediaQuery.of(context).padding.bottom),
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
          _buildChapterNavigation(chapterIndex),
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

  // 构建章节末尾的导航按钮
  Widget _buildChapterNavigation(int chapterIndex) {
    final bool hasPrevious = chapterIndex > 0;
    final bool hasNext = chapterIndex < _currentBook.chapters.length - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 64.0, bottom: 24.0),
      child: Column(
        children: [
          Divider(color: _currentTheme.font.withOpacity(0.2)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Opacity(
                opacity: hasPrevious ? 1.0 : 0.3,
                child: OutlinedButton(
                  onPressed: hasPrevious ? () => _jumpToChapter(chapterIndex - 1) : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _currentTheme.font.withOpacity(0.5)),
                    foregroundColor: _currentTheme.font,
                  ),
                  child: const Icon(Icons.arrow_back),
                ),
              ),
              Opacity(
                opacity: hasNext ? 1.0 : 0.3,
                child: OutlinedButton(
                  onPressed: hasNext ? () => _jumpToChapter(chapterIndex + 1) : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _currentTheme.font.withOpacity(0.5)),
                    foregroundColor: _currentTheme.font,
                  ),
                  child: const Icon(Icons.arrow_forward),
                ),
              ),
            ],
          ),
        ],
      ),
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
            isSelected: _currentTheme.id == theme.id, // 通过id判断是否选中
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

// 主题选择的自定义小组件
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
            theme.name, // UI上依然显示中文名
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
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: InteractiveViewer(
                      clipBehavior: Clip.none,
                      child: Image.file(File(imagePath)),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          tooltip: '重新生成',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRegenerate();
                          },
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.movie_creation_outlined, color: Colors.white),
                          tooltip: '图生视频',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onGenerateVideo();
                          },
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                          tooltip: '删除',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onDelete();
                          },
                        ),
                      ],
                    ),
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

// 视频缩略图组件
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

  void _showEnlargedVideo(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _VideoPlayerDialog(
          videoPath: widget.videoPath,
          onDelete: widget.onDelete,
        );
      },
    );
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
                onEnter: (_) => _controller.play(),
                onExit: (_) => _controller.pause(),
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

// 视频播放悬浮组件
class _VideoPlayerDialog extends StatefulWidget {
  final String videoPath;
  final VoidCallback onDelete;

  const _VideoPlayerDialog({required this.videoPath, required this.onDelete});

  @override
  _VideoPlayerDialogState createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {}, // 防止点击视频关闭对话框
                child: Center(
                  child: _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : const CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {}, // 防止点击视频关闭对话框
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: '删除视频',
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