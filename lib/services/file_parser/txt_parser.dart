// lib/services/file_parser/txt_parser.dart

import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

/// TXT 文件专属解析器。
class TxtParser {
  // 章节标题的核心正则表达式，匹配多种常见的章节格式。
  // 例如 "第一章", "第100回", "序章", "楔子" 等。
  static final _chapterRegex = RegExp(
    r'^\s*(?:'
    r'第\s*[零〇一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+\s*[章节回集卷部篇]' // 匹配 "第...章/回" 等
    r'|'
    r'[第]*\s*[一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章节回集卷部篇]' // 匹配 "第...章/回"（中文数字）
    r'|'
    r'[一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+[．、.]' // 匹配 "1." 或 "一、" 等
    r'|'
    r'序章|楔子|前言|序言|序|引子|后记|尾声|番外|锲子|终章|结语|附录' // 匹配特殊章节名
    r')\s*.*?$',
    caseSensitive: false,
    multiLine: false,
  );

  // 用于识别分隔符的正则表达式，例如 "---" 或 "==="。
  static final _separatorRegex = RegExp(r'^[\-=*~]{3,}$');

  /// 解析 TXT 文件，返回章节结构列表。
  /// [cachedPath] 是 TXT 文件在缓存区的路径。
  static Future<List<ChapterStructure>> parse(String cachedPath) async {
    final file = File(cachedPath);
    final content = await file.readAsString();
    
    // 统一换行符为 '\n'，以兼容不同操作系统的文件。
    final normalizedContent = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedContent.split('\n');
    
    final sourceFilename = p.basename(cachedPath);
    
    // 调用核心解析逻辑
    return _parseLines(rawLines, sourceFilename);
  }

  /// 核心解析逻辑：处理行列表，识别并构建章节。
  /// 将此逻辑分离出来，便于单元测试和代码维护。
  static List<ChapterStructure> _parseLines(List<String> rawLines, String sourceFilename) {
    // 1. 查找所有可能是章节标题的候选行。
    final List<_ChapterCandidate> candidates = _findChapterCandidates(rawLines);
    
    // 2. 如果没有找到任何章节，则将整个文件视为一个大章节。
    if (candidates.isEmpty) {
      return _createSingleChapter(rawLines, sourceFilename);
    }
    
    // 3. 如果找到了章节候选，则根据它们来构建章节列表。
    return _buildChaptersFromCandidates(rawLines, candidates, sourceFilename);
  }

  /// 遍历所有行，找出所有可能的章节标题候选者。
  static List<_ChapterCandidate> _findChapterCandidates(List<String> lines) {
    final List<_ChapterCandidate> candidates = [];
    
    for (int i = 0; i < lines.length; i++) {
      final lineText = lines[i].trim();
      
      if (lineText.isEmpty) continue; // 跳过空行
      
      // 检查是否为被分隔符包围的标题格式（如 --- 标题 ---）
      final separatorCandidate = _checkSeparatorTitle(lines, i);
      if (separatorCandidate != null) {
        candidates.add(separatorCandidate);
        i = separatorCandidate.endIndex; // 跳过已处理的行
        continue;
      }
      
      // 检查是否匹配标准的章节标题正则表达式
      if (_isValidChapterTitle(lineText)) {
        candidates.add(_ChapterCandidate(
          title: lineText,
          startIndex: i,
          endIndex: i,
        ));
      }
    }
    
    // 对找到的候选进行过滤，去除可能是误判的标题
    return _filterValidCandidates(candidates, lines);
  }

  /// 检查由分隔符包围的标题格式，例如：
  /// ---
  /// 章节标题
  /// ---
  static _ChapterCandidate? _checkSeparatorTitle(List<String> lines, int index) {
    if (index + 2 >= lines.length) return null;
    
    final line1 = lines[index].trim();
    final line2 = lines[index + 1].trim();
    final line3 = lines[index + 2].trim();
    
    if (_separatorRegex.hasMatch(line1) && 
        _separatorRegex.hasMatch(line3) &&
        line2.isNotEmpty && 
        line2.length < 50) { // 标题不应过长
      return _ChapterCandidate(
        title: line2,
        startIndex: index,
        endIndex: index + 2,
      );
    }
    
    return null;
  }

  /// 验证一个字符串是否为有效的章节标题。
  static bool _isValidChapterTitle(String text) {
    if (text.length > 100) return false; // 标题太长，可能是普通段落
    if (text.length < 2) return false;   // 标题太短，也可能是误判
    
    return _chapterRegex.hasMatch(text);
  }

  /// 过滤章节候选列表，去除无效的候选。
  /// 主要逻辑是检查章节之间是否有足够的内容，如果两个“标题”之间内容过少，则可能其中一个是误判。
  static List<_ChapterCandidate> _filterValidCandidates(
    List<_ChapterCandidate> candidates, 
    List<String> lines
  ) {
    if (candidates.length <= 1) return candidates; // 只有一个候选，无需过滤
    
    final List<_ChapterCandidate> filtered = [];
    
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      
      // 计算当前候选标题与下一个标题之间的有效内容行数
      final nextIndex = i + 1 < candidates.length 
        ? candidates[i + 1].startIndex 
        : lines.length;
      
      final contentLines = _countContentLines(
        lines, 
        candidate.endIndex + 1, 
        nextIndex
      );
      
      // 如果章节间内容行数太少（少于3行），则可能是一个误判的标题，予以丢弃
      if (contentLines >= 3 || i == candidates.length - 1) { // 最后一个候选总是保留
        filtered.add(candidate);
      }
    }
    
    return filtered;
  }

  /// 统计指定行范围内的非空行数。
  static int _countContentLines(List<String> lines, int start, int end) {
    int count = 0;
    for (int i = start; i < end && i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  /// 根据最终确定的章节候选列表，构建完整的章节结构列表。
  static List<ChapterStructure> _buildChaptersFromCandidates(
    List<String> lines, 
    List<_ChapterCandidate> candidates, 
    String sourceFilename
  ) {
    final List<ChapterStructure> chapters = [];
    int globalLineIdCounter = 0;
    
    // 处理第一个章节标题之前的内容，将其作为“前言”
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
    
    // 遍历所有章节候选，提取它们之间的内容作为章节正文
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

  /// 从原始行列表中提取指定范围的行，并转换为 LineStructure 对象列表。
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
      if (lineText.isNotEmpty) { // 忽略空行
        result.add(LineStructure(
          id: lineId++,
          text: lineText,
          sourceInfo: sourceFilename,
          originalContent: lines[i], // 保留原始行（带空格）
        ));
      }
    }
    
    return result;
  }

  /// 当没有检测到任何章节时，创建一个包含全文的单一章节。
  static List<ChapterStructure> _createSingleChapter(
    List<String> lines, 
    String sourceFilename
  ) {
    final chapterLines = _extractLinesFromRange(
      lines, 0, lines.length, sourceFilename, 0
    );
    
    if (chapterLines.isEmpty) return []; // 如果文件为空，则返回空列表
    
    return [
      ChapterStructure(
        id: const Uuid().v4(),
        title: "全文", // 默认章节标题
        sourceFile: sourceFilename,
        lines: chapterLines,
      )
    ];
  }
}

/// 内部数据结构，用于暂存章节标题候选及其在文件中的位置信息。
class _ChapterCandidate {
  final String title;      // 候选标题文本
  final int startIndex;   // 标题在原始行列表中的起始行号
  final int endIndex;     // 标题在原始行列表中的结束行号（主要用于多行标题，如分隔符格式）
  
  _ChapterCandidate({
    required this.title,
    required this.startIndex,
    required this.endIndex,
  });
}