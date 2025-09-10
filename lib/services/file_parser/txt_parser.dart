// lib/services/file_parser/txt_parser.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

class TxtParser {
  // 一个强大的正则表达式，用于匹配多种常见的章节标题格式
  // 涵盖 "第一章", "第1章", "章一", "楔子", "序章", "一.", "第一集 ... 第三回" 等格式
  static final _chapterRegex = RegExp(
    r'^\s*(?:' // Start with a non-capturing group for the whole pattern
    r'第\s*[零〇一二三四五六七八九十百千万\d]+\s*[章节回集卷部篇]' // e.g., 第一章, 第10回, 第一集
    r'|'
    r'章\s*[一二三四五六七八九十百千万]+' // e.g., 章一, 章二十三
    r'|'
    r'[一二三四五六七八九十百千万]+[．、.]' // e.g., 一. 二、
    r'|'
    r'序章|楔子|前言|序言|序|引子|后记|尾声|番外|锲子' // Special chapter titles
    r')\s*.*$', // Match the rest of the line as part of the title
    caseSensitive: false,
    multiLine: false,
  );
  // 并将其移出循环以提高性能，只编译一次
  static final _separatorRegex = RegExp(r'^-{5,}$|={5,}$|\*{5,}$');


  /// 解析 TXT，返回章节列表
  static Future<List<ChapterStructure>> parse(String cachedPath) async {
    final file = File(cachedPath);
    final rawLines = await file.readAsLines();

    final List<ChapterStructure> chapters = [];
    List<LineStructure> currentChapterLines = [];
    // 为第一章之前的内容（如序言）设置一个默认标题
    String currentChapterTitle = "前言";
    int globalLineIdCounter = 0;

    for (int i = 0; i < rawLines.length; i++) {
      final lineText = rawLines[i].trim();
      bool isChapterTitle = false;
      String newTitle = '';

      // 检查是否是章节标题
      if (lineText.isNotEmpty) {
        // 规则1: 检查由分隔符包围的标题, e.g., --- 锲子 ---
        // *** FIX & IMPROVEMENT *** 使用预编译的正则表达式
        if (_separatorRegex.hasMatch(lineText)) {
           if (i + 2 < rawLines.length && rawLines[i+2].trim() == lineText) {
             final potentialTitle = rawLines[i+1].trim();
             // 避免误判，标题通常较短
             if (potentialTitle.isNotEmpty && potentialTitle.length < 30) {
                isChapterTitle = true;
                newTitle = potentialTitle;
                i += 2; // 跳过标题行和下一个分隔符行
             }
           }
        }

        // 规则2: 如果不是分隔符格式，则使用正则表达式检查
        if (!isChapterTitle && _chapterRegex.hasMatch(lineText)) {
          // 避免将过长的段落误判为章节标题
          if (lineText.length < 50) {
             isChapterTitle = true;
             newTitle = lineText;
          }
        }
      }

      if (isChapterTitle) {
        // 保存上一章节的内容（如果存在）
        if (currentChapterLines.isNotEmpty) {
          chapters.add(ChapterStructure(
            title: currentChapterTitle,
            sourceFile: p.basename(cachedPath),
            lines: List.from(currentChapterLines),
          ));
        }
        // 开始新章节
        currentChapterLines.clear();
        currentChapterTitle = newTitle;
      } else {
        // 如果不是章节标题，则作为正文行添加
        if (lineText.isNotEmpty) {
          currentChapterLines.add(LineStructure(
            id: globalLineIdCounter++,
            text: lineText,
            lineNumberInSourceFile: i + 1,
            originalContent: rawLines[i],
          ));
        }
      }
    }

    // 添加最后一个章节
    if (currentChapterLines.isNotEmpty) {
      chapters.add(ChapterStructure(
        title: currentChapterTitle,
        sourceFile: p.basename(cachedPath),
        lines: currentChapterLines,
      ));
    }

    // 如果没有识别到任何章节（例如纯文本文件），则将所有内容视为一个章节
    if (chapters.isEmpty) {
        final List<LineStructure> lines = [];
        globalLineIdCounter = 0;
        for (int i = 0; i < rawLines.length; i++) {
          final lineText = rawLines[i].trim();
          if (lineText.isNotEmpty) {
            lines.add(LineStructure(
              id: globalLineIdCounter++,
              text: lineText,
              lineNumberInSourceFile: i + 1,
              originalContent: rawLines[i],
            ));
          }
        }
        if (lines.isNotEmpty) {
           chapters.add(ChapterStructure(
            title: "全文",
            sourceFile: p.basename(cachedPath),
            lines: lines,
          ));
        }
    }

    return chapters;
  }
}