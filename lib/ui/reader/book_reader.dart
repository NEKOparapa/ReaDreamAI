// lib/ui/reader/book_reader.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/book.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_executor/single_illustration_executor.dart';


class _ReaderTheme {
  final Color background;
  final Color font;
  final String name;

  const _ReaderTheme({required this.name, required this.background, required this.font});

  static const List<_ReaderTheme> themes = [
    _ReaderTheme(name: '默认', background: Color(0xFFFFFFFF), font: Color(0xFF333333)),
    _ReaderTheme(name: '护眼', background: Color(0xFFF0F5E9), font: Color(0xFF58452D)),
    _ReaderTheme(name: '夜间', background: Color(0xFF222222), font: Color(0xFFBBBBBB)),
    _ReaderTheme(name: '羊皮纸', background: Color(0xFFF5EFDC), font: Color(0xFF8B4513)),
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

  // --- 页面状态和设置 ---
  final PageController _pageController = PageController();
  int _currentChapterIndex = 0;

  // --- UI 可见性控制 ---
  final ValueNotifier<bool> _isToolbarVisible = ValueNotifier(true);

  // --- 阅读器设置 ---
  _ReaderTheme _currentTheme = _ReaderTheme.themes[0];
  double _fontSize = 18.0;
  String _fontFamily = 'SystemDefault';
  DisplayMode _displayMode = DisplayMode.original;

  @override
  void initState() {
    super.initState();
    _currentBook = widget.book;
    _toggleSystemUI(_isToolbarVisible.value);
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

  // 任务处理逻辑保持不变，但非常清晰，无需修改
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

  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return _ReaderSettingsPanel(
          initialTheme: _currentTheme,
          initialFontSize: _fontSize,
          initialFontFamily: _fontFamily,
          initialDisplayMode: _displayMode,
          onSettingsChanged: (theme, fontSize, fontFamily, displayMode) {
            setState(() {
              _currentTheme = theme;
              _fontSize = fontSize;
              _fontFamily = fontFamily;
              _displayMode = displayMode;
            });
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
    return Scaffold(
      backgroundColor: _currentTheme.background,
      body: ValueListenableBuilder<bool>(
        valueListenable: _isToolbarVisible,
        builder: (context, isVisible, child) {
          return Stack(
            children: [
              // 主内容区域
              child!,
              // 顶部工具栏 (AppBar)
              _buildTopToolbar(isVisible),
              // 底部工具栏
              _buildBottomToolbar(isVisible),
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
                    padding: const EdgeInsets.symmetric(horizontal: 56.0), // 左右留出空间，避免与按钮重叠
                    child: Text(
                      chapterTitle,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      '${_currentChapterIndex + 1}/${_currentBook.chapters.length}',
                      style: const TextStyle(fontSize: 14.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // 构建底部工具栏
  Widget _buildBottomToolbar(bool isVisible) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: isVisible ? 0 : -kBottomNavigationBarHeight - MediaQuery.of(context).padding.bottom,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).bottomAppBarTheme.color?.withOpacity(0.95),
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            height: kBottomNavigationBarHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: '上一章',
                  onPressed: _currentChapterIndex > 0 ? () => _jumpToChapter(_currentChapterIndex - 1) : null,
                ),
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
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: '下一章',
                  onPressed: _currentChapterIndex < _currentBook.chapters.length - 1 ? () => _jumpToChapter(_currentChapterIndex + 1) : null,
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
        // 在翻页模式下，每一页都是一个可以独立滚动的ListView, 以防单章内容超出一屏
        return SingleChildScrollView(
          child: _buildChapterContent(chapterIndex),
        );
      },
    );
  }

  // 构建章节内容 Widget (提取出的公共部分)
  Widget _buildChapterContent(int chapterIndex) {
    final chapter = _currentBook.chapters[chapterIndex];
    
    return Padding(
      padding: EdgeInsets.fromLTRB(24.0, 48.0 + kToolbarHeight + MediaQuery.of(context).padding.top, 24.0, 48.0 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 章节标题
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
          // 章节内容
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

      if (line.illustrationPaths.isNotEmpty) {
        submitTextBlock();
        contentWidgets.add(
          _IllustrationGallery(
            imagePaths: line.illustrationPaths,
            onRegenerate: () => _regenerateIllustrationForLine(line, chapter),
            onDelete: (path) => _deleteIllustration(path, line),
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
        height: 1.7, // 行间距
        color: _currentTheme.font,
        fontFamily: _fontFamily == 'SystemDefault' ? null : _fontFamily,
      ),
      textAlign: TextAlign.justify,
      contextMenuBuilder: (context, state) => _buildTextContextMenu(context, state, linesInfo),
    );
  }
}


// 独立、有状态的设置面板 Widget
class _ReaderSettingsPanel extends StatefulWidget {
  final _ReaderTheme initialTheme;
  final double initialFontSize;
  final String initialFontFamily;
  final DisplayMode initialDisplayMode;
  final Function(
    _ReaderTheme theme,
    double fontSize,
    String fontFamily,
    DisplayMode displayMode,
  ) onSettingsChanged;

  const _ReaderSettingsPanel({
    required this.initialTheme,
    required this.initialFontSize,
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
  late String _fontFamily;
  late DisplayMode _displayMode;

  @override
  void initState() {
    super.initState();
    _currentTheme = widget.initialTheme;
    _fontSize = widget.initialFontSize;
    _fontFamily = widget.initialFontFamily;
    _displayMode = widget.initialDisplayMode;
  }

  void _notifyParent() {
    widget.onSettingsChanged(_currentTheme, _fontSize, _fontFamily, _displayMode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),

            _buildSectionTitle('显示模式'),
            SizedBox(
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
            const SizedBox(height: 20),

            _buildSectionTitle('背景主题'),
            Wrap(
              spacing: 12,
              children: _ReaderTheme.themes.map((theme) {
                return ChoiceChip(
                  label: Text(theme.name),
                  selected: _currentTheme.name == theme.name,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _currentTheme = theme);
                      _notifyParent();
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            _buildSectionTitle('字号大小'),
            Slider(
              value: _fontSize,
              min: 12.0, max: 32.0, divisions: 20,
              label: _fontSize.round().toString(),
              onChanged: (value) {
                setState(() => _fontSize = value);
                _notifyParent();
              },
            ),

            _buildSectionTitle('字体'),
            DropdownButton<String>(
              value: _fontFamily,
              isExpanded: true,
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
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}


// 插图画廊组件
class _IllustrationGallery extends StatelessWidget {
  final List<String> imagePaths;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onDelete;

  const _IllustrationGallery({
    required this.imagePaths,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 16.0,
        alignment: WrapAlignment.center,
        children: imagePaths.map((path) {
          return _ImageTile(
            key: ValueKey(path),
            imagePath: path,
            onRegenerate: onRegenerate,
            onDelete: () => onDelete(path),
          );
        }).toList(),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  const _ImageTile({
    super.key,
    required this.imagePath,
    required this.onRegenerate,
    required this.onDelete,
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
                        const SizedBox(width: 24),
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