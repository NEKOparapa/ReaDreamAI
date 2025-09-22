// lib/services/epub_exporter/epub_exporter.dart

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../base/log/log_service.dart'; 
import '../../models/book.dart';

// 声明本库包含的其他文件部分
part 'txt_source_exporter.dart';
part 'epub_source_exporter.dart';
part 'media_helper.dart';

/// EpubExporter 门面类，提供统一的导出入口。
class EpubExporter {
  /// 导出一本书籍为 EPUB 文件。
  static Future<void> exportBook(Book book) async {
    // 1: 弹出文件保存对话框，让用户选择保存路径和文件名。
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出书籍',
      fileName: '${book.title}.epub',
      allowedExtensions: ['epub'],
    );

    // 如果用户取消了选择，则直接返回。
    if (outputPath == null) return;

    try {
      // 2: 根据书籍的原始文件类型
      if (book.fileType == 'txt') {
        // 如果源文件是 TXT，则从头构建一个新的 EPUB 文件。
        await _TxtSourceExporter().export(book, outputPath);
      } else if (book.fileType == 'epub') {
        // 如果源文件是 EPUB，则解包、修改并重新打包。
        await _EpubSourceExporter().export(book, outputPath);
      } else {
        // 对于不支持的类型，抛出异常。
        throw Exception('不支持的文件类型: ${book.fileType}');
      }
      LogService.instance.success('书籍 "${book.title}" 导出成功: $outputPath');
    } catch (e, stackTrace) {
      // 3: 捕获导出过程中任何环节的异常，并记录错误日志。
      LogService.instance.error('导出过程出现错误', e, stackTrace);
      // 向上层抛出异常，以便 UI 层可以捕获并显示错误信息给用户。
      throw Exception('导出失败: $e');
    }
  }
}