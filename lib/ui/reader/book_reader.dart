// lib/ui/reader/book_reader.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/book.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_executor/single_illustration_executor.dart';

// 定义每页大致显示的行数，用于预分页
const int _linesPerPage = 40;

class BookReaderPage extends StatefulWidget {
  final Book book;

  const BookReaderPage({super.key, required this.book});

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  late Book _currentBook;
  bool _isGenerating = false;
  int? _generatingLineId;
  final _executor = SingleIllustrationExecutor.instance;

  // --- 翻页相关变量 ---
  late List<List<(LineStructure, ChapterStructure)>> _pages;
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentBook = widget.book;
    _initializePagination();
  }

  // 初始化分页数据
  void _initializePagination() {
    _pages = [];
    List<(LineStructure, ChapterStructure)> currentPageLines = [];

    for (final chapter in _currentBook.chapters) {
      for (final line in chapter.lines) {
        currentPageLines.add((line, chapter));

        // 当达到每页行数或章节结束时，分割页面
        if (currentPageLines.length >= _linesPerPage) {
          _pages.add(List.from(currentPageLines));
          currentPageLines.clear();
        }
      }
    }
    // 添加最后一页（如果还有剩余行）
    if (currentPageLines.isNotEmpty) {
      _pages.add(currentPageLines);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleIllustrationTask(Future<void> taskFunction, int lineId) async {
    if (_isGenerating) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有任务在生成中，请稍候...')));
      return;
    }
    setState(() {
      _isGenerating = true;
      _generatingLineId = lineId;
    });
    try {
      await taskFunction;
      await CacheManager().saveBookDetail(_currentBook);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('插图生成成功！')));
      }
    } catch (e) {
      print("生成插图失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatingLineId = null;
        });
      }
    }
  }

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
      setState(() {
        line.illustrationPaths.remove(imagePath);
      });
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
        // 回滚UI更改
        setState(() {
          line.illustrationPaths.add(imagePath);
        });
      }
    }
  }

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
          targetLine.id,
    );
  }

  Future<void> _regenerateIllustrationForLine(LineStructure line, ChapterStructure chapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');
    await _handleIllustrationTask(
          _executor.regenerateIllustration(
            chapter: chapter,
            line: line,
            imageSaveDir: illustrationsDir.path,
          ),
          line.id,
    );
  }

  // --- 上下文菜单构建器 ---
  Widget _buildTextContextMenu(
    BuildContext context,
    EditableTextState state,
    List<({LineStructure line, ChapterStructure chapter})> linesInBlock,
  ) {
    // 【BUG修复】
    // 使用 state.textEditingValue.selection.start 和 .end 替代 .baseOffset 和 .extentOffset
    // 这样可以确保无论用户从左到右还是从右到左选择，start 的值总是小于或等于 end 的值。
    final selection = state.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) {
      // 如果没有有效的选择或选择是折叠的（即只有一个光标），则只显示默认按钮
      return AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: state.contextMenuButtonItems,
        anchors: state.contextMenuAnchors,
      );
    }
    
    // 使用修复后的 selection.start 和 selection.end
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
    
    // 核心逻辑：从划选位置找到对应的行
    final int selectionEndOffset = selection.extentOffset; // 使用 .extentOffset 来定位结束行
    int cumulativeLength = 0;
    var target = linesInBlock.last; 
    
    for (final lineInfo in linesInBlock) {
      final line = lineInfo.line;
      final hasTranslation = line.translatedText != null && line.translatedText!.isNotEmpty;
      int currentLineLength = line.text.length + 1; // +1 for '\n'
      if (hasTranslation) {
        currentLineLength += line.translatedText!.length + 1; // +1 for '\n'
      }

      if (selectionEndOffset <= cumulativeLength + currentLineLength) {
        target = lineInfo;
        break;
      }
      cumulativeLength += currentLineLength;
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
            _generateIllustrationForSelection(selectedText, target.line, target.chapter);
          },
          label: '为划选内容生成插图',
        ),
      ],
      anchors: state.contextMenuAnchors,
    );
  }


  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentBook.title),
        actions: [
          if (_pages.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text('第 ${_currentPageIndex + 1} / ${_pages.length} 页'),
              ),
            ),
        ],
      ),
      body: _pages.isEmpty
          ? const Center(child: Text('书籍内容为空'))
          : PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
              },
              itemBuilder: (context, pageIndex) {
                return _buildPageContent(pageIndex);
              },
            ),
    );
  }

  Widget _buildPageContent(int pageIndex) {
    final pageLines = _pages[pageIndex];
    if (pageLines.isEmpty) return const SizedBox.shrink();

    List<Widget> contentWidgets = [];
    List<TextSpan> currentTextSpans = [];
    List<({LineStructure line, ChapterStructure chapter})> currentBlockLines = [];

    void flushTextBuffer() {
      if (currentTextSpans.isNotEmpty) {
        final blockLines = List.of(currentBlockLines);
        contentWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(children: currentTextSpans),
                    contextMenuBuilder: (context, state) =>
                        _buildTextContextMenu(context, state, blockLines),
                  ),
                ),
                if (_isGenerating &&
                    blockLines.any((info) => info.line.id == _generatingLineId))
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0, top: 4.0),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                  )
              ],
            ),
          ),
        );
        currentTextSpans = [];
        currentBlockLines = [];
      }
    }

    for (final lineInfo in pageLines) {
      final (line, chapter) = lineInfo;

      if (line.illustrationPaths.isNotEmpty) {
        flushTextBuffer();

        contentWidgets.add(_buildSingleLineText(line, chapter));

        contentWidgets.add(
          _IllustrationGallery(
            imagePaths: line.illustrationPaths,
            onRegenerate: () => _regenerateIllustrationForLine(line, chapter),
            onDelete: (path) => _deleteIllustration(path, line),
          ),
        );
      } else {
        final hasTranslation = line.translatedText != null && line.translatedText!.isNotEmpty;
        if (hasTranslation) {
          currentTextSpans.add(TextSpan(
            text: '${line.translatedText!}\n',
            style: const TextStyle(fontSize: 16, height: 1.6),
          ));
        }
        currentTextSpans.add(TextSpan(
          text: '${line.text}\n',
          style: TextStyle(
            fontSize: hasTranslation ? 13 : 16,
            height: 1.5,
            color: hasTranslation ? Colors.grey[600] : Colors.black87,
          ),
        ));
        currentBlockLines.add((line: line, chapter: chapter));
      }
    }

    flushTextBuffer();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      children: contentWidgets,
    );
  }

  Widget _buildSingleLineText(LineStructure line, ChapterStructure chapter) {
    List<TextSpan> textSpans = [];
    final hasTranslation = line.translatedText != null && line.translatedText!.isNotEmpty;

    if (hasTranslation) {
      textSpans.add(TextSpan(
        text: '${line.translatedText!}\n',
        style: const TextStyle(fontSize: 16, height: 1.6),
      ));
    }
    textSpans.add(TextSpan(
      text: line.text,
      style: TextStyle(
        fontSize: hasTranslation ? 13 : 16,
        height: 1.5,
        color: hasTranslation ? Colors.grey[600] : Colors.black87,
      ),
    ));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: textSpans),
              contextMenuBuilder: (context, state) =>
                  _buildTextContextMenu(context, state, [(line: line, chapter: chapter)]),
            ),
          ),
          if (_isGenerating && _generatingLineId == line.id)
            const Padding(
              padding: EdgeInsets.only(left: 8.0, top: 4.0),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.0),
              ),
            )
        ],
      ),
    );
  }
}

// 插图画廊组件 (保持不变)
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
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
      child: Wrap(
        spacing: 12.0,
        runSpacing: 12.0,
        children: imagePaths
            .map((path) => _ImageTile(
          key: ValueKey(path),
          imagePath: path,
          onRegenerate: onRegenerate,
          onDelete: () => onDelete(path),
        ))
            .toList(),
      ),
    );
  }
}

// 单个图片瓦片组件 (保持不变)
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
        return Dialog(
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
              Container(
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
            ],
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
        constraints: const BoxConstraints(maxWidth: 400),
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
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              imageFile,
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                child: const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}