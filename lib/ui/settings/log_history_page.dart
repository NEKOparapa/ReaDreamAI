import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../base/log/log_service.dart';

class LogHistoryPage extends StatefulWidget {
  const LogHistoryPage({super.key});

  @override
  State<LogHistoryPage> createState() => _LogHistoryPageState();
}

class _LogHistoryPageState extends State<LogHistoryPage> {
  final _logService = LogService.instance;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听日志变化，如果滚动条在底部，则自动滚动
    _logService.logNotifier.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    _logService.logNotifier.removeListener(_scrollToBottom);
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollToBottom() {
    // 在下一帧绘制完成后执行滚动，确保ListView已经更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _exportLogs() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在打包日志...')),
    );

    final zipFilePath = await _logService.exportLogsToZip();

    if (zipFilePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('错误：日志打包失败！')),
        );
      }
      return;
    }

    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '请选择保存位置:',
      fileName: 'AiReaa_Logs_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    
    if (outputFile != null) {
      try {
        final zipFile = File(zipFilePath);
        await zipFile.copy(outputFile);
        await zipFile.parent.delete(recursive: true); // 清理临时文件
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('日志已成功导出到: $outputFile')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('错误：保存日志文件失败: $e')),
          );
        }
      }
    } else {
        // 用户取消了保存对话框
        final tempDir = File(zipFilePath).parent;
        await tempDir.delete(recursive: true); // 清理临时文件
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: '导出日志压缩包',
            onPressed: _exportLogs,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<LogEntry>>(
        valueListenable: _logService.logNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty) {
            return const Center(child: Text('暂无日志记录'));
          }
          // 列表反转，最新的日志显示在最下面
          final reversedLogs = logs.reversed.toList();
          return ListView.builder(
            controller: _scrollController,
            reverse: true, // 关键属性，让列表从底部开始显示
            itemCount: reversedLogs.length,
            itemBuilder: (context, index) {
              final log = reversedLogs[index];
              return _LogEntryTile(log: log);
            },
          );
        },
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry log;
  const _LogEntryTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconData = _getIconForLevel(log.level);
    final color = _getColorForLevel(log.level, theme);
    final time = DateFormat('HH:mm:ss.SSS').format(log.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '[$time]',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ),
          Icon(iconData, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              log.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace', // 使用等宽字体以获得更好的对齐效果
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warn:
        return Icons.warning_amber_outlined;
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.success:
        return Icons.check_circle_outline;
    }
  }

  Color _getColorForLevel(LogLevel level, ThemeData theme) {
    switch (level) {
      case LogLevel.info:
        return theme.colorScheme.primary;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return theme.colorScheme.error;
      case LogLevel.success:
        return Colors.green;
    }
  }
}