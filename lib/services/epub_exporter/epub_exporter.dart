// lib/services/epub_exporter/epub_exporter.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // 导入 Uint8List
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../base/log/log_service.dart';
import '../../models/book.dart';

part 'txt_source_exporter.dart';
part 'epub_source_exporter.dart';
part 'media_helper.dart';

/// EpubExporter 门面类，提供统一的导出入口。
class EpubExporter {
  /// 生成一本书籍的 EPUB 文件字节数据。
  /// 成功时返回 Uint8List，失败时抛出异常。
  static Future<Uint8List> generateEpubBytes(Book book) async {
    try {
      // 1. 在内存中生成 EPUB 文件的字节数据
      Uint8List? epubBytes;
      if (book.fileType == 'txt') {
        // 从 TXT 源构建新的 EPUB 数据
        epubBytes = await _TxtSourceExporter().export(book);
      } else if (book.fileType == 'epub') {
        // 从 EPUB 源修改并重新打包数据
        epubBytes = await _EpubSourceExporter().export(book);
      } else {
        throw Exception('不支持的文件类型: ${book.fileType}');
      }

      // 如果生成失败，则抛出异常
      if (epubBytes == null) {
        throw Exception('生成 EPUB 文件失败，返回了空数据。');
      }
      
      LogService.instance.success('书籍 "${book.title}" 的 EPUB 字节数据生成成功。');
      // 2. 直接返回生成的字节数据
      return epubBytes;

    } catch (e, stackTrace) {
      // 捕获导出过程中任何环节的异常
      LogService.instance.error('生成 EPUB 字节数据时出现错误', e, stackTrace);
      // 向上层抛出异常，以便 UI 层可以捕获并显示错误信息给用户。
      // 这里可以重新包装异常，提供更清晰的错误信息
      throw Exception('导出失败: $e');
    }
  }
}