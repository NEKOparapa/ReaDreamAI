// lib/ui/pages/reader_page.dart

import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/task_executor/single_illustration_executor.dart'; // 导入新服务


class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late Book _currentBook; // 使用可变状态来持有Book对象

  // 用于显示生成状态
  bool _isGenerating = false;
  int? _generatingLineId;

  // 依赖新拆分的服务
  final _executor = SingleIllustrationExecutor.instance;

  @override
  void initState() {
    super.initState();
    _currentBook = widget.book; // 初始化时使用传入的book
  }
  
  // 统一处理生成任务的UI状态和错误
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
      await taskFunction; // 执行传入的具体生成任务
      
      // 执行成功后，Book对象已被修改，只需保存并刷新UI
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

  // 调用新服务执行“此处生成插图”
  Future<void> _generateIllustrationForLine(LineStructure line, ChapterStructure chapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');
    
    await _handleIllustrationTask(
      _executor.generateIllustrationHere(
        book: _currentBook,
        chapter: chapter,
        line: line,
        imageSaveDir: illustrationsDir.path,
      ),
      line.id
    );
  }

  // 调用新服务执行“重新生成插图”
  Future<void> _regenerateIllustrationForLine(LineStructure line, ChapterStructure chapter) async {
    final illustrationsDir = await CacheManager().getOrCreateBookSubDir(_currentBook.id, 'illustrations');

    await _handleIllustrationTask(
      _executor.regenerateIllustration(
        chapter: chapter,
        line: line,
        imageSaveDir: illustrationsDir.path,
      ),
      line.id
    );
  }

  // 删除图片 (逻辑不变)
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
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片已删除')));
        }
      } catch (e) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除文件失败: $e'), backgroundColor: Colors.red));
        }
        // 如果文件删除失败，把路径加回去以保持同步
        setState(() {
          line.illustrationPaths.add(imagePath);
        });
      }
    }
  }

  // 显示右键菜单 (逻辑不变)
  void _showContextMenu(BuildContext context, TapDownDetails details, LineStructure line, ChapterStructure chapter) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(details.globalPosition & const Size(40, 40), Offset.zero & overlay.size),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          onTap: () => _generateIllustrationForLine(line, chapter),
          child: const Row(children: [Icon(Icons.add_photo_alternate_outlined), SizedBox(width: 8), Text('此处生成插图')]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentBook.title),
      ),
      body: _buildBookView(),
    );
  }

  // 统一的视图构建器，现在同时支持 TXT 和 EPUB
  Widget _buildBookView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      itemCount: _calculateTotalItemCount(),
      itemBuilder: (context, index) {
        final item = _getItemForIndex(index);

        // 如果item是章节，渲染章节标题
        if (item is ChapterStructure) {
          // 不为只有一个“全文”章节的TXT文件显示标题
          if (_currentBook.chapters.length == 1 && item.title == "全文") {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
            child: Text(
              item.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          );
        } 
        // 如果item是行数据，渲染行内容
        else if (item is (LineStructure, ChapterStructure)) {
          final (line, chapter) = item;
          return _LineWidget(
            key: ValueKey(line.id),
            line: line,
            isGenerating: _isGenerating && _generatingLineId == line.id,
            onSecondaryTapDown: (details) => _showContextMenu(context, details, line, chapter),
            onRegenerate: () => _regenerateIllustrationForLine(line, chapter), // 绑定到新的重新生成函数
            onDelete: (path) => _deleteIllustration(path, line),
          );
        }
        return const SizedBox.shrink(); // 理论上不会发生
      },
    );
  }

  // 辅助函数：计算ListView的总项目数（所有章节标题+所有行）
  int _calculateTotalItemCount() {
    return _currentBook.chapters.fold(0, (sum, chapter) => sum + 1 + chapter.lines.length);
  }
  
  // 辅助函数：根据扁平化的索引，获取对应的章节或行数据
  dynamic _getItemForIndex(int index) {
    int currentIndex = 0;
    for (final chapter in _currentBook.chapters) {
      // 检查索引是否为章节标题
      if (index == currentIndex) {
        return chapter;
      }
      currentIndex++;
      // 检查索引是否在该章节的行范围内
      if (index < currentIndex + chapter.lines.length) {
        final lineIndex = index - currentIndex;
        return (chapter.lines[lineIndex], chapter);
      }
      currentIndex += chapter.lines.length;
    }
    return null; // 理论上不会发生
  }
}



class _LineWidget extends StatelessWidget {
  final LineStructure line;
  final bool isGenerating;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onDelete;

  const _LineWidget({
    super.key,
    required this.line,
    required this.isGenerating,
    this.onSecondaryTapDown,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // ADDED: 判断是否有有效的译文
    final hasTranslation = line.translatedText != null && line.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onSecondaryTapDown: onSecondaryTapDown,
          child: Container(
            color: Colors.transparent, // 使整个区域可点击
            padding: const EdgeInsets.symmetric(vertical: 4.0), // 增加一些垂直内边距
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MODIFIED: 使用 Column 同时显示译文和原文
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 如果有译文，显示译文
                      if (hasTranslation)
                        SelectableText(
                          line.translatedText!,
                          style: const TextStyle(fontSize: 16, height: 1.6),
                        ),
                      
                      // 显示原文
                      // 如果有译文，原文的样式会变淡变小，以作区分
                      SelectableText(
                        line.text,
                        style: TextStyle(
                          fontSize: hasTranslation ? 13 : 16,
                          height: 1.5,
                          color: hasTranslation ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                    ],
                  )
                ),
                if (isGenerating)
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0, top: 4.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                  )
              ],
            ),
          ),
        ),
        if (line.illustrationPaths.isNotEmpty)
          _IllustrationGallery(
            imagePaths: line.illustrationPaths,
            onRegenerate: onRegenerate,
            onDelete: onDelete,
          ),
        const SizedBox(height: 8), // 行间距
      ],
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Wrap(
        spacing: 12.0,
        runSpacing: 12.0,
        children: imagePaths.map((path) => _ImageTile(
          key: ValueKey(path),
          imagePath: path,
          onRegenerate: onRegenerate,
          onDelete: () => onDelete(path),
        )).toList(),
      ),
    );
  }
}

class _ImageTile extends StatefulWidget {
  final String imagePath;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  const _ImageTile({
    super.key,
    required this.imagePath,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _isHovering = false;
  
  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.imagePath);
    if (!imageFile.existsSync()) {
      return Container(
        width: 200, height: 200,
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40)),
      );
    }
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: 200,
          constraints: const BoxConstraints(maxHeight: 250),
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Image.file(
                imageFile,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
                ),
              ),
              AnimatedOpacity(
                opacity: _isHovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        tooltip: '重新生成',
                        onPressed: widget.onRegenerate,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                        tooltip: '删除',
                        onPressed: widget.onDelete,
                      ),
                    ],
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