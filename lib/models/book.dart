// lib/models/book.dart

import 'package:json_annotation/json_annotation.dart';
part 'book.g.dart'; // 运行 flutter pub run build_runner build 来生成这个文件

// 行结构：存储单行文本及其元数据
@JsonSerializable()
class LineStructure {
  final int id;
  final String text;
  final int lineNumberInSourceFile;
  final String originalContent;
  final List<String> illustrationPaths;
  final String? sceneDescription;
  final String? translatedText;

  LineStructure({
    required this.id,
    required this.text,
    required this.lineNumberInSourceFile,
    required this.originalContent,
    this.illustrationPaths = const [],
    this.sceneDescription,
    this.translatedText, // 新增
  });

  // copyWith 方法，便于更新
  LineStructure copyWith({
    String? translatedText,
  }) {
    return LineStructure(
      id: id,
      text: text,
      lineNumberInSourceFile: lineNumberInSourceFile,
      originalContent: originalContent,
      illustrationPaths: illustrationPaths,
      sceneDescription: sceneDescription,
      translatedText: translatedText ?? this.translatedText,
    );
  }

  factory LineStructure.fromJson(Map<String, dynamic> json) => _$LineStructureFromJson(json);
  Map<String, dynamic> toJson() => _$LineStructureToJson(this);
}

/// 章节结构：存储章节标题和包含的所有行
@JsonSerializable(explicitToJson: true) // 确保有 explicitToJson: true
class ChapterStructure {
  final String title; // 存储章节标题
  final String sourceFile; // 存储章节对应的源文件路径
  final List<LineStructure> lines; // 存储章节中的所有行

  ChapterStructure({
    required this.title,
    required this.sourceFile,
    required this.lines,
  });

  // 在特定行号添加插图
  void addIllustrationsToLine(int lineNumber, List<String> paths, String? description) {
    try {
      final line = lines.firstWhere((l) => l.lineNumberInSourceFile == lineNumber);
      // 创建一个新的 LineStructure 实例来替换旧的，以保持不可变性
      final lineIndex = lines.indexOf(line);
      if (lineIndex != -1) {
        lines[lineIndex] = LineStructure(
          id: line.id,
          text: line.text,
          lineNumberInSourceFile: line.lineNumberInSourceFile,
          originalContent: line.originalContent,
          illustrationPaths: [...line.illustrationPaths, ...paths], // 合并而不是覆盖
          sceneDescription: description ?? line.sceneDescription, // 更新描述
        );
      }
    } catch (e) {
      print('Error: Could not find line with number $lineNumber to add illustration.');
    }
  }

  factory ChapterStructure.fromJson(Map<String, dynamic> json) => _$ChapterStructureFromJson(json);
  Map<String, dynamic> toJson() => _$ChapterStructureToJson(this);
}

/// 书籍模型：代表一本完整解析后的书籍，包含了所有数据
@JsonSerializable(explicitToJson: true) // 确保有 explicitToJson: true
class Book {
  final String id; // 书籍的唯一标识符
  final String title; // 书籍标题
  final String fileType; // 书籍文件类型
  final String originalPath; // 书籍原始文件的绝对路径
  final String cachedPath; // 书籍缓存文件的绝对路径
  final String? coverImagePath; // 新增封面图片路径字段
  final List<ChapterStructure> chapters; // 存储书籍的所有章节

  Book({
    required this.id,
    required this.title,
    required this.fileType,
    required this.originalPath,
    required this.cachedPath,
    this.coverImagePath, // 添加到构造函数
    required this.chapters,
  });

  factory Book.fromJson(Map<String, dynamic> json) => _$BookFromJson(json);
  Map<String, dynamic> toJson() => _$BookToJson(this);
}