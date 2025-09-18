// lib/services/epub_exporter/epub_exporter.dart

// 统一管理所有依赖
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/book.dart';

// 声明本库包含的其他文件部分
part 'txt_source_exporter.dart';
part 'epub_source_exporter.dart';
part 'media_helper.dart';

/// EpubExporter 门面类，提供统一的导出入口。
/// 项目中其他地方只需要 import 这个文件即可。
class EpubExporter {
  static Future<void> exportBook(Book book) async {
    // 1. 让用户选择保存路径
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出书籍',
      fileName: '${book.title}.epub',
      allowedExtensions: ['epub'],
    );

    if (outputPath == null) return;

    try {
      // 2. 根据书籍原始类型选择对应的导出器
      if (book.fileType == 'txt') {
        await _TxtSourceExporter().export(book, outputPath);
      } else if (book.fileType == 'epub') {
        await _EpubSourceExporter().export(book, outputPath);
      } else {
        throw Exception('不支持的文件类型: ${book.fileType}');
      }
    } catch (e, stackTrace) {
      print('导出过程出现错误: $e');
      print(stackTrace);
      throw Exception('导出失败: $e');
    }
  }
}