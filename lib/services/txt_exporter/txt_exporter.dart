// lib/services/txt_exporter/txt_exporter.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../models/book.dart';
import '../../base/log/log_service.dart';

class TxtExporter {
  /// 将书籍内容导出为 TXT 格式并打包进 ZIP
  static Future<Uint8List> exportBookToTxtZip(Book book) async {
    try {
      final buffer = StringBuffer();

      // ==========================================
      // 1. 写入书籍元数据 (大标题格式)
      // ==========================================
      buffer.writeln('=' * 25);
      buffer.writeln('  《${book.title}》');
      buffer.writeln('=' * 25);
      buffer.writeln(); 

      // 写入简介
      if (book.introduction != null && book.introduction!.trim().isNotEmpty) {
        buffer.writeln('【小说简介】');
        buffer.writeln(book.introduction!.trim());
        buffer.writeln();
      }

      // ==========================================
      // 2. 遍历章节写入内容
      // ==========================================
      for (final entry in book.chapters.asMap().entries) {
        final index = entry.key + 1; // 序号从1开始
        final chapter = entry.value;
        
        // ---章节间隔 ---
        // 在新章节开始前，插入4个空行，让章节之间有明显的视觉区隔
        buffer.writeln('\n' * 2); 

        // --- 章节标题格式化 ---
        // 使用虚线框住章节标题，使其显眼
        buffer.writeln('-' * 40);
        buffer.writeln('  第 $index 章 ${chapter.title}');
        buffer.writeln('-' * 40);
        
        // 写入章节简述（如有）
        if (chapter.chapterSummary != null && chapter.chapterSummary!.trim().isNotEmpty) {
          buffer.writeln('【章节简述】');
          buffer.writeln(chapter.chapterSummary!.trim());
          buffer.writeln();
          buffer.writeln();
        }

        // 写入章节正文
        for (final line in chapter.lines) {
          final text = line.text;
          
          if (text.trim().isNotEmpty) {
            // 段首缩进两个空格
            buffer.writeln('  $text'); 
          }
        }
      }

      // ==========================================
      // 3. 创建 ZIP 包
      // ==========================================
      final archive = Archive();
      
      // 将内容编码为 UTF-8
      final txtContent = buffer.toString();
      final txtBytes = utf8.encode(txtContent);

      // 构建压缩包内的文件名 (去除特殊字符以防文件名非法)
      String safeTitle = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (safeTitle.isEmpty) safeTitle = "exported_book";
      
      // 添加 TXT 文件到压缩包
      archive.addFile(ArchiveFile(
        '$safeTitle.txt',
        txtBytes.length,
        txtBytes,
      ));

      // 4. 编码并返回
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);

      LogService.instance.success('书籍 TXT压缩包生成成功: ${book.title}');
      return Uint8List.fromList(zipData);

    } catch (e, s) {
      LogService.instance.error('导出 TXT 失败', e, s);
      rethrow;
    }
  }
}