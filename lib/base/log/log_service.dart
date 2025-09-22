/// lib/base/log/log_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import '../config_service.dart';

// 日志级别枚举
enum LogLevel { info, warn, error, success }

// 日志条目模型
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  LogEntry({required this.timestamp, required this.level, required this.message});
}

/// 日志服务类 (单例)
class LogService {
  static final LogService instance = LogService._internal();
  factory LogService() => instance;
  LogService._internal();

  final List<LogEntry> _logs = [];
  late final String _logDirectoryPath;
  late final File _logFile;
  final int _maxLogEntriesInMemory = 1000; // 内存中最多保留1000条日志

  // 使用 ValueNotifier 实现响应式UI更新
  final ValueNotifier<List<LogEntry>> logNotifier = ValueNotifier([]);

  /// 初始化日志服务
  Future<void> init() async {
    // 依赖 ConfigService 来获取应用目录
    final appDir = ConfigService().getAppDirectoryPath();
    _logDirectoryPath = p.join(appDir, 'Logs');
    final logDir = Directory(_logDirectoryPath);
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File(p.join(_logDirectoryPath, 'app.log'));
    if (!await _logFile.exists()) {
      await _logFile.create();
    }
    info("日志服务已初始化，日志文件路径: ${_logFile.path}");
  }

  /// 内部记录日志的核心方法
  Future<void> _log(LogLevel level, String message) async {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );

    // 添加到内存列表
    _logs.add(entry);
    if (_logs.length > _maxLogEntriesInMemory) {
      _logs.removeAt(0); // 如果超过上限，移除最旧的一条
    }

    // 更新UI监听器
    logNotifier.value = List.from(_logs);

    // 格式化并写入文件
    final levelStr = level.toString().split('.').last.toUpperCase();
    // 构建日志行时不再包含时间戳
    final logLine = '[$levelStr] $message';

    // 在控制台也输出同样的内容。
    // 使用 kDebugMode 判断，只在调试模式下打印，避免在 release 版本中输出日志。
    if (kDebugMode) {
      print(logLine);
    }

    // 异步写入文件，避免阻塞UI
    try {
      // 写入文件时再添加换行符
      await _logFile.writeAsString('$logLine\n', mode: FileMode.append);
    } catch (e) {
      // 如果日志文件写入失败，也在控制台打印错误
      if (kDebugMode) {
        print("Failed to write to log file: $e");
      }
    }
  }

  // --- 公共日志方法 ---

  /// 普通信息日志
  void info(String message) => _log(LogLevel.info, message);

  /// 警告日志
  void warn(String message) => _log(LogLevel.warn, message);

  /// 错误日志
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    String fullMessage = message;
    if (error != null) {
      fullMessage += '\nError: $error';
    }
    if (stackTrace != null) {
      fullMessage += '\nStackTrace: $stackTrace';
    }
    _log(LogLevel.error, fullMessage);
  }

  /// 成功日志
  void success(String message) => _log(LogLevel.success, message);
  
  /// 导出日志目录为ZIP压缩包
  Future<String?> exportLogsToZip() async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('log_export_');
      final zipFilePath = p.join(tempDir.path, 'logs.zip');
      
      var encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      encoder.addDirectory(Directory(_logDirectoryPath));
      encoder.close();

      info('日志已成功打包到: $zipFilePath');
      return zipFilePath;
    } catch (e, s) {
      error('导出日志失败', e, s);
      return null;
    }
  }
}