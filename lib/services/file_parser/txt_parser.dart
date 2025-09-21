// lib/services/file_parser/txt_parser.dart

import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

class TxtParser {
  // 优化后的章节标题正则表达式 - 更精确和高效
  static final _chapterRegex = RegExp(
    r'^\s*(?:'
    r'第\s*[零〇一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+\s*[章节回集卷部篇]'
    r'|'
    r'[第]*\s*[一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章节回集卷部篇]'
    r'|'
    r'[一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+[．、.]'
    r'|'
    r'序章|楔子|前言|序言|序|引子|后记|尾声|番外|锲子|终章|结语|附录'
    r')\s*.*?$',
    caseSensitive: false,
    multiLine: false,
  );

  // 分隔符正则表达式
  static final _separatorRegex = RegExp(r'^[\-=*~]{3,}$');

  /// 解析 TXT，返回章节列表
  static Future<List<ChapterStructure>> parse(String cachedPath) async {
    final file = File(cachedPath);
    final content = await file.readAsString();
    
    // 统一换行符并分割行
    final normalizedContent = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedContent.split('\n');
    
    final sourceFilename = p.basename(cachedPath);
    
    return _parseLines(rawLines, sourceFilename);
  }

  /// 核心解析逻辑 - 分离出来便于测试和维护
  static List<ChapterStructure> _parseLines(List<String> rawLines, String sourceFilename) {
    final List<ChapterStructure> chapters = [];
    final List<_ChapterCandidate> candidates = _findChapterCandidates(rawLines);
    
    if (candidates.isEmpty) {
      // 没有找到章节，将整个文件作为一个章节
      return _createSingleChapter(rawLines, sourceFilename);
    }
    
    return _buildChaptersFromCandidates(rawLines, candidates, sourceFilename);
  }

  /// 查找所有可能的章节标题候选
  static List<_ChapterCandidate> _findChapterCandidates(List<String> lines) {
    final List<_ChapterCandidate> candidates = [];
    
    for (int i = 0; i < lines.length; i++) {
      final lineText = lines[i].trim();
      
      if (lineText.isEmpty) continue;
      
      // 检查分隔符包围的标题格式
      final separatorCandidate = _checkSeparatorTitle(lines, i);
      if (separatorCandidate != null) {
        candidates.add(separatorCandidate);
        i = separatorCandidate.endIndex; // 跳过已处理的行
        continue;
      }
      
      // 检查标准章节标题格式
      if (_isValidChapterTitle(lineText)) {
        candidates.add(_ChapterCandidate(
          title: lineText,
          startIndex: i,
          endIndex: i,
        ));
      }
    }
    
    return _filterValidCandidates(candidates, lines);
  }

  /// 检查分隔符包围的标题
  static _ChapterCandidate? _checkSeparatorTitle(List<String> lines, int index) {
    if (index + 2 >= lines.length) return null;
    
    final line1 = lines[index].trim();
    final line2 = lines[index + 1].trim();
    final line3 = lines[index + 2].trim();
    
    // 检查 --- 标题 --- 格式
    if (_separatorRegex.hasMatch(line1) && 
        _separatorRegex.hasMatch(line3) &&
        line2.isNotEmpty && 
        line2.length < 50) {
      return _ChapterCandidate(
        title: line2,
        startIndex: index,
        endIndex: index + 2,
      );
    }
    
    return null;
  }

  /// 验证是否为有效的章节标题
  static bool _isValidChapterTitle(String text) {
    if (text.length > 100) return false; // 太长的不太可能是标题
    if (text.length < 2) return false;   // 太短的也不太可能
    
    return _chapterRegex.hasMatch(text);
  }

  /// 过滤有效的章节候选
  static List<_ChapterCandidate> _filterValidCandidates(
    List<_ChapterCandidate> candidates, 
    List<String> lines
  ) {
    if (candidates.length <= 1) return candidates;
    
    final List<_ChapterCandidate> filtered = [];
    
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      
      // 检查章节之间是否有足够的内容
      final nextIndex = i + 1 < candidates.length 
        ? candidates[i + 1].startIndex 
        : lines.length;
      
      final contentLines = _countContentLines(
        lines, 
        candidate.endIndex + 1, 
        nextIndex
      );
      
      // 如果章节间内容太少，可能是误判
      if (contentLines >= 3 || i == candidates.length - 1) {
        filtered.add(candidate);
      }
    }
    
    return filtered;
  }

  /// 统计有效内容行数
  static int _countContentLines(List<String> lines, int start, int end) {
    int count = 0;
    for (int i = start; i < end && i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  /// 从候选列表构建章节
  static List<ChapterStructure> _buildChaptersFromCandidates(
    List<String> lines, 
    List<_ChapterCandidate> candidates, 
    String sourceFilename
  ) {
    final List<ChapterStructure> chapters = [];
    int globalLineIdCounter = 0;
    
    // 处理第一章之前的内容
    if (candidates.first.startIndex > 0) {
      final preChapterLines = _extractLinesFromRange(
        lines, 0, candidates.first.startIndex, sourceFilename, globalLineIdCounter
      );
      if (preChapterLines.isNotEmpty) {
        chapters.add(ChapterStructure(
          id: const Uuid().v4(),
          title: "前言",
          sourceFile: sourceFilename,
          lines: preChapterLines,
        ));
        globalLineIdCounter += preChapterLines.length;
      }
    }
    
    // 处理各个章节
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final nextStart = i + 1 < candidates.length 
        ? candidates[i + 1].startIndex 
        : lines.length;
      
      final chapterLines = _extractLinesFromRange(
        lines, 
        candidate.endIndex + 1, 
        nextStart, 
        sourceFilename, 
        globalLineIdCounter
      );
      
      if (chapterLines.isNotEmpty) {
        chapters.add(ChapterStructure(
          id: const Uuid().v4(),
          title: candidate.title,
          sourceFile: sourceFilename,
          lines: chapterLines,
        ));
        globalLineIdCounter += chapterLines.length;
      }
    }
    
    return chapters;
  }

  /// 从指定范围提取行内容
  static List<LineStructure> _extractLinesFromRange(
    List<String> lines, 
    int start, 
    int end, 
    String sourceFilename, 
    int startLineId
  ) {
    final List<LineStructure> result = [];
    int lineId = startLineId;
    
    for (int i = start; i < end && i < lines.length; i++) {
      final lineText = lines[i].trim();
      if (lineText.isNotEmpty) {
        result.add(LineStructure(
          id: lineId++,
          text: lineText,
          sourceInfo: sourceFilename,
          originalContent: lines[i],
        ));
      }
    }
    
    return result;
  }

  /// 创建单一章节（当没有检测到章节分割时）
  static List<ChapterStructure> _createSingleChapter(
    List<String> lines, 
    String sourceFilename
  ) {
    final chapterLines = _extractLinesFromRange(
      lines, 0, lines.length, sourceFilename, 0
    );
    
    if (chapterLines.isEmpty) return [];
    
    return [
      ChapterStructure(
        id: const Uuid().v4(),
        title: "全文",
        sourceFile: sourceFilename,
        lines: chapterLines,
      )
    ];
  }
}

/// 章节候选数据结构
class _ChapterCandidate {
  final String title;
  final int startIndex;
  final int endIndex;
  
  _ChapterCandidate({
    required this.title,
    required this.startIndex,
    required this.endIndex,
  });
}
