import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/epub_exporter/epub_exporter.dart';
import '../../base/log/log_service.dart';

// 定义导出格式的枚举
enum ExportFormat {
  epub,
  cachePackage,
}

// 定义对话框内部状态的枚举
enum _ExportState {
  selecting, // 初始状态，选择格式
  exporting, // 正在导出
  success,   // 导出成功
  error,     // 导出失败
}

class ExportBookDialog extends StatefulWidget {
  // 接收需要导出的书籍条目
  final BookshelfEntry entry;

  const ExportBookDialog({
    super.key,
    required this.entry,
  });

  @override
  State<ExportBookDialog> createState() => _ExportBookDialogState();
}

class _ExportBookDialogState extends State<ExportBookDialog> {
  // 对话框当前的状态
  _ExportState _currentState = _ExportState.selecting;
  // 选中的导出格式
  ExportFormat? _selectedFormat = ExportFormat.epub;
  // 用于存储成功或失败后的提示信息
  String _message = '';

  // 这个值基于初始选择界面的大致高度设定
  static const double _minContentHeight = 160.0;


  /// 开始导出流程
  Future<void> _startExport() async {
    if (_selectedFormat == null) return;

    // 1. 更新UI为“导出中”状态
    setState(() {
      _currentState = _ExportState.exporting;
      _message = '正在准备书籍数据...';
    });

    try {
      // 2. 加载书籍完整详情
      final book = await CacheManager().loadBookDetail(widget.entry.id);
      if (book == null) {
        throw Exception('加载书籍详情失败，无法导出。');
      }

      // 3. 根据选择的格式执行操作
      switch (_selectedFormat!) {
        case ExportFormat.epub:
          setState(() => _message = '正在生成 EPUB 文件...');
          // 3.1 调用服务生成文件字节
          final epubBytes = await EpubExporter.generateEpubBytes(book);

          setState(() => _message = '请选择保存位置...');
          // 3.2 弹出文件保存对话框
          final String? outputPath = await FilePicker.platform.saveFile(
            dialogTitle: '导出书籍',
            fileName: '${book.title}.epub',
            bytes: epubBytes,
          );

          // 3.3 根据保存结果更新UI
          if (outputPath != null) {
            setState(() {
              _currentState = _ExportState.success;
              _message = '《${book.title}》已成功导出到:\n$outputPath';
            });
          } else {
            // 用户取消了保存
            setState(() {
              _currentState = _ExportState.selecting; // 回到选择界面
              _message = '';
            });
          }
          break;
        case ExportFormat.cachePackage:
          // 预留功能
           setState(() {
              _currentState = _ExportState.error;
              _message = '缓存包导出功能正在开发中。';
            });
          break;
      }
    } catch (e, s) {
      LogService.instance.error('在对话框中导出失败', e, s);
      // 4. 捕获任何异常，并更新UI为“错误”状态
      setState(() {
        _currentState = _ExportState.error;
        _message = '导出失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            _buildTitle(),
            const SizedBox(height: 16),
            // ConstrainedBox 保证了最小高度，避免跳动
            // AnimatedSwitcher 提供了平滑的淡入淡出过渡效果
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minContentHeight),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildContentForState(),
              ),
            ),
            const SizedBox(height: 24),
            // 操作按钮（根据状态切换）
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// 构建标题
  Widget _buildTitle() {
    String title;
    switch (_currentState) {
      case _ExportState.selecting:
        title = '选择导出格式';
        break;
      case _ExportState.exporting:
        title = '正在导出';
        break;
      case _ExportState.success:
        title = '导出成功';
        break;
      case _ExportState.error:
        title = '导出失败';
        break;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        // 只有在选择状态下才显示关闭按钮
        if (_currentState == _ExportState.selecting)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  /// 添加 Key 是为了让 AnimatedSwitcher 能够正确识别 Widget 的变化
  Widget _buildContentForState() {
    switch (_currentState) {
      case _ExportState.selecting:
        return KeyedSubtree(
          key: const ValueKey('selecting'),
          child: _buildSelectionContent(),
        );
      case _ExportState.exporting:
        return KeyedSubtree(
          key: const ValueKey('exporting'),
          child: _buildProgressContent(),
        );
      case _ExportState.success:
        return KeyedSubtree(
          key: const ValueKey('success'),
          child: _buildResultContent(isError: false),
        );
      case _ExportState.error:
        return KeyedSubtree(
          key: const ValueKey('error'),
          child: _buildResultContent(isError: true),
        );
    }
  }

  /// 构建格式选择界面
  Widget _buildSelectionContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
      children: [
        RadioListTile<ExportFormat>(
          title: const Text('EPUB 格式'),
          subtitle: const Text('标准电子书格式，兼容大多数阅读器。'),
          value: ExportFormat.epub,
          groupValue: _selectedFormat,
          onChanged: (value) => setState(() => _selectedFormat = value),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        const Divider(height: 8),
        RadioListTile<ExportFormat>(
          title: const Text('缓存包 (开发中)'),
          subtitle: const Text('用于备份或迁移，包含所有元数据和媒体文件。'),
          value: ExportFormat.cachePackage,
          groupValue: _selectedFormat,
          onChanged: null,
        ),
      ],
    );
  }

  /// 构建导出中界面
  Widget _buildProgressContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(_message, textAlign: TextAlign.center),
      ],
    );
  }

  /// 构建成功或失败的结果界面
  Widget _buildResultContent({required bool isError}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          color: isError ? Colors.red : Colors.green,
          size: 60,
        ),
        const SizedBox(height: 16),
        SelectableText(_message, textAlign: TextAlign.center),
      ],
    );
  }

  /// 根据当前状态构建底部操作按钮
  Widget _buildActions() {
    switch (_currentState) {
      case _ExportState.selecting:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: _selectedFormat == ExportFormat.epub ? _startExport : null,
              child: const Text('确认导出'),
            ),
          ],
        );
      case _ExportState.exporting:
        // 导出中不显示任何按钮，防止用户误操作
        return const SizedBox(height: 48); // 用SizedBox占位，保持总高度一致
      case _ExportState.success:
      case _ExportState.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
    }
  }
}