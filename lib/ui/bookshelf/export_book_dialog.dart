// lib/ui/bookshelf/export_book_dialog.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/bookshelf_entry.dart';
import '../../services/cache_manager/cache_manager.dart';
import '../../services/epub_exporter/epub_exporter.dart';
import '../../services/media_exporter/media_exporter.dart';
import '../../services/txt_exporter/txt_exporter.dart'; // [新增] 导入 TXT 导出服务
import '../../base/log/log_service.dart';

// [修改] 添加 txt 格式枚举
enum ExportFormat { epub, mediaPackage, cachePackage, txt }

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

  const ExportBookDialog({super.key, required this.entry});

  @override
  State<ExportBookDialog> createState() => _ExportBookDialogState();
}

class _ExportBookDialogState extends State<ExportBookDialog> {
  // 对话框当前的状态
  _ExportState _currentState = _ExportState.selecting;
  // 选中的导出格式
  ExportFormat? _selectedFormat;
  // 用于存储成功或失败后的提示信息
  String _message = '';

  // 这个值基于初始选择界面的大致高度设定
  static const double _minContentHeight = 160.0;

  @override
  void initState() {
    super.initState();
    // 根据书籍类型设置默认的导出格式
    if (widget.entry.fileType == 'videoBook') {
      _selectedFormat = ExportFormat.mediaPackage;
    } else {
      _selectedFormat = ExportFormat.epub;
    }
  }

  /// 开始导出流程
  Future<void> _startExport() async {
    if (_selectedFormat == null) return;

    // 1. 更新UI为“导出中”状态
    setState(() {
      _currentState = _ExportState.exporting;
      _message = '正在准备数据...';
    });

    try {
      // 2. 根据选择的格式执行操作
      switch (_selectedFormat!) {
        case ExportFormat.epub:
          setState(() => _message = '正在加载书籍详情...');
          final book = await CacheManager().loadBookDetail(widget.entry.id);
          if (book == null) {
            throw Exception('加载书籍详情失败，无法导出。');
          }

          setState(() => _message = '正在生成 EPUB 文件...');
          final epubBytes = await EpubExporter.generateEpubBytes(book);

          setState(() => _message = '请选择保存位置...');

          final String? epubPath = await FilePicker.platform.saveFile(
            dialogTitle: '导出 EPUB',
            fileName: '${book.title}.epub',
            type: FileType.custom,
            allowedExtensions: ['epub'],
            bytes: epubBytes, // Android/iOS 必须传此参数
          );

          if (epubPath != null) {
            // 桌面端需要手动写入
            if (!Platform.isAndroid && !Platform.isIOS) {
              await File(epubPath).writeAsBytes(epubBytes);
            }

            setState(() {
              _currentState = _ExportState.success;
              _message = '《${book.title}》已成功导出到:\n$epubPath';
            });
          } else {
            setState(() => _currentState = _ExportState.selecting);
          }
          break;

        // [新增] TXT (ZIP) 导出逻辑
        case ExportFormat.txt:
          setState(() => _message = '正在加载书籍详情...');
          final book = await CacheManager().loadBookDetail(widget.entry.id);
          if (book == null) {
            throw Exception('加载书籍详情失败，无法导出。');
          }

          setState(() => _message = '正在生成 TXT 压缩包...');
          // 调用新的服务生成 ZIP 数据
          final zipBytes = await TxtExporter.exportBookToTxtZip(book);

          setState(() => _message = '请选择保存位置...');
          final String? zipPath = await FilePicker.platform.saveFile(
            dialogTitle: '导出 TXT',
            fileName: '${book.title}_txt.zip', // 保存为 zip
            type: FileType.custom,
            allowedExtensions: ['zip'],
            bytes: zipBytes,
          );

          if (zipPath != null) {
            if (!Platform.isAndroid && !Platform.isIOS) {
              await File(zipPath).writeAsBytes(zipBytes);
            }
            setState(() {
              _currentState = _ExportState.success;
              _message = '《${book.title}》的文本已打包导出到:\n$zipPath';
            });
          } else {
            setState(() => _currentState = _ExportState.selecting);
          }
          break;

        case ExportFormat.mediaPackage:
          setState(() => _message = '正在收集所有媒体文件...');
          // 调用新服务生成 ZIP 字节流
          final zipBytes = await MediaExporter.exportVideoBookMediaAsZip(
            widget.entry,
          );

          setState(() => _message = '请选择保存位置...');

          final String? zipPath = await FilePicker.platform.saveFile(
            dialogTitle: '导出媒体包',
            fileName: '${widget.entry.title}_媒体文件.zip',
            type: FileType.custom,
            allowedExtensions: ['zip'],
            bytes: zipBytes,
          );

          if (zipPath != null) {
            if (!Platform.isAndroid && !Platform.isIOS) {
              await File(zipPath).writeAsBytes(zipBytes);
            }

            setState(() {
              _currentState = _ExportState.success;
              _message = '《${widget.entry.title}》的媒体文件已成功导出到:\n$zipPath';
            });
          } else {
            // 用户取消保存
            setState(() => _currentState = _ExportState.selecting);
          }
          break;

        case ExportFormat.cachePackage:
          setState(() {
            _currentState = _ExportState.error;
            _message = '缓存包导出功能正在开发中。';
          });
          break;
      }
    } catch (e, s) {
      LogService.instance.error('在对话框中导出失败', e, s);
      // 4. 捕获任何异常，并更新UI为“错误”状态
      if (mounted) {
        setState(() {
          _currentState = _ExportState.error;
          _message = '导出失败: $e';
        });
      }
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
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
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

  /// 构建格式选择界面，使其根据书籍类型动态变化
  Widget _buildSelectionContent() {
    // 如果是视频书
    if (widget.entry.fileType == 'videoBook') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RadioListTile<ExportFormat>(
            title: const Text('导出媒体'),
            subtitle: const Text('将所有图片和视频按章节-场景分类并打包成ZIP。'),
            value: ExportFormat.mediaPackage,
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
            onChanged: null, // 禁用
          ),
        ],
      );
    }
    // 如果是普通书籍 (TXT/EPUB)
    else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RadioListTile<ExportFormat>(
            title: const Text('EPUB 格式'),
            subtitle: const Text('标准电子书格式，保留样式和插图。'),
            value: ExportFormat.epub,
            groupValue: _selectedFormat,
            onChanged: (value) => setState(() => _selectedFormat = value),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          const Divider(height: 8),

          // [新增] TXT 选项
          RadioListTile<ExportFormat>(
            title: const Text('TXT 纯文本'),
            subtitle: const Text('包含标题、简介、章节内容，不含媒体资源。'),
            value: ExportFormat.txt,
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
            onChanged: null, // 禁用
          ),
        ],
      );
    }
  }

  /// 构建导出中界面
  Widget _buildProgressContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
      mainAxisAlignment: MainAxisAlignment.center,
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
    // 辅助函数：检查当前选中的格式是否可用
    bool isExportEnabled() {
      if (_selectedFormat == null) return false;
      // 缓存包导出功能未开放，始终禁用
      if (_selectedFormat == ExportFormat.cachePackage) return false;
      return true;
    }

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
              onPressed: isExportEnabled() ? _startExport : null,
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