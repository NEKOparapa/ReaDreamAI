// lib/models/book.dart

import 'package:json_annotation/json_annotation.dart';
part 'book.g.dart'; //运行 flutter pub run build_runner build --delete-conflicting-outputs 来生成这个文件

// 行结构：存储单行文本及其元数据
@JsonSerializable()
class LineStructure {
  final int id;  // 每行的唯一标识符
  final String text; // 行文本内容
  final int lineNumberInSourceFile; // 在源文件中的行号
  final String originalContent; // 原始内容
  final List<String> illustrationPaths; // 插图路径列表
  final List<String> videoPaths;  // 视频路径列表
  final String? sceneDescription; // 场景描述(绘图标签prompt)
  final String? translatedText; // 翻译后的文本

  LineStructure({
    required this.id,
    required this.text,
    required this.lineNumberInSourceFile,
    required this.originalContent,
    this.illustrationPaths = const [],
    this.videoPaths = const [], 
    this.sceneDescription,
    this.translatedText,
  });

  // copyWith 方法，便于更新
  LineStructure copyWith({
    String? translatedText,
    List<String>? illustrationPaths,
    List<String>? videoPaths,
    String? sceneDescription,
  }) {
    return LineStructure(
      id: id,
      text: text,
      lineNumberInSourceFile: lineNumberInSourceFile,
      originalContent: originalContent,
      illustrationPaths: illustrationPaths ?? this.illustrationPaths,
      videoPaths: videoPaths ?? this.videoPaths,
      sceneDescription: sceneDescription ?? this.sceneDescription,
      translatedText: translatedText ?? this.translatedText,
    );
  }

  factory LineStructure.fromJson(Map<String, dynamic> json) => _$LineStructureFromJson(json);
  Map<String, dynamic> toJson() => _$LineStructureToJson(this);
}

/// 章节结构：存储章节标题和包含的所有行
@JsonSerializable(explicitToJson: true)
class ChapterStructure {
  final String title;
  final String sourceFile;
  final List<LineStructure> lines;

  ChapterStructure({
    required this.title,
    required this.sourceFile,
    required this.lines,
  });

  // 在特定行号添加插图
  void addIllustrationsToLine(int lineNumber, List<String> paths, String? description) {
    try {
      final line = lines.firstWhere((l) => l.lineNumberInSourceFile == lineNumber);
      final lineIndex = lines.indexOf(line);
      if (lineIndex != -1) {
        lines[lineIndex] = line.copyWith(
          illustrationPaths: [...line.illustrationPaths, ...paths],
          sceneDescription: description ?? line.sceneDescription,
        );
      }
    } catch (e) {
      print('Error: Could not find line with number $lineNumber to add illustration.');
    }
  }

  // 在特定行号添加视频
  void addVideosToLine(int lineNumber, List<String> paths) {
    try {
      final line = lines.firstWhere((l) => l.lineNumberInSourceFile == lineNumber);
      final lineIndex = lines.indexOf(line);
      if (lineIndex != -1) {
        lines[lineIndex] = line.copyWith(
          videoPaths: [...line.videoPaths, ...paths],
        );
      }
    } catch (e) {
      print('Error: Could not find line with number $lineNumber to add video.');
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
    this.coverImagePath,
    required this.chapters,
  });

  factory Book.fromJson(Map<String, dynamic> json) => _$BookFromJson(json);
  Map<String, dynamic> toJson() => _$BookToJson(this);
}