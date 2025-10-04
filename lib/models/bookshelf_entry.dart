// lib/models/bookshelf_entry.dart

import 'package:json_annotation/json_annotation.dart';
part 'bookshelf_entry.g.dart';

// 任务可能存在的状态
enum TaskStatus {
  notStarted, // 任务未创建
  queued, // 排队中
  running, // 正在运行
  paused, // 已暂停
  completed, // 已完成
  failed, // 已失败
  canceled, // 已取消
}

// 单个任务区块的状态
enum ChunkStatus {
  pending, // 待处理
  running, // 处理中
  completed, // 已完成
  failed, // 已失败
}

// 插图生成子任务区块
@JsonSerializable()
class IllustrationTaskChunk {
  final String id;
  final String chapterId;
  final int startLineId;
  final int endLineId;
  final int scenesToGenerate;
  ChunkStatus status;

  IllustrationTaskChunk({
    required this.id,
    required this.chapterId,
    required this.startLineId,
    required this.endLineId,
    required this.scenesToGenerate,
    this.status = ChunkStatus.pending,
  });

  factory IllustrationTaskChunk.fromJson(Map<String, dynamic> json) => _$IllustrationTaskChunkFromJson(json);
  Map<String, dynamic> toJson() => _$IllustrationTaskChunkToJson(this);
}

// 翻译任务的子任务区块
@JsonSerializable()
class TranslationTaskChunk {
  final String id;
  final String chapterId;
  final int startLineId;
  final int endLineId;
  ChunkStatus status;

  TranslationTaskChunk({
    required this.id,
    required this.chapterId,
    required this.startLineId,
    required this.endLineId,
    this.status = ChunkStatus.pending,
  });

  factory TranslationTaskChunk.fromJson(Map<String, dynamic> json) => _$TranslationTaskChunkFromJson(json);
  Map<String, dynamic> toJson() => _$TranslationTaskChunkToJson(this);
}

// 视频生成子任务区块
@JsonSerializable()
class VideoGenerationTaskChunk {
  final String id;
  final String chapterId;
  final int lineId;
  final String sourceImagePath; // 关键字段：源图片路径
  ChunkStatus status;

  VideoGenerationTaskChunk({
    required this.id,
    required this.chapterId,
    required this.lineId,
    required this.sourceImagePath,
    this.status = ChunkStatus.pending,
  });

  factory VideoGenerationTaskChunk.fromJson(Map<String, dynamic> json) =>
      _$VideoGenerationTaskChunkFromJson(json);
  Map<String, dynamic> toJson() => _$VideoGenerationTaskChunkToJson(this);
}


// 书架缓存文件中的单个条目
@JsonSerializable(explicitToJson: true)
class BookshelfEntry {
  final String id; // 书籍ID，与Book模型中的id一致
  final String title;
  final String originalPath;
  final String fileType;
  final String subCachePath;
  final String? coverImagePath; 

  // --- 插图任务字段 ---
  TaskStatus status;
  List<IllustrationTaskChunk> taskChunks;
  String? errorMessage;
  DateTime? createdAt;
  DateTime? updatedAt;

  // --- 翻译任务字段 ---
  @JsonKey(defaultValue: TaskStatus.notStarted)
  TaskStatus translationStatus;
  @JsonKey(defaultValue: [])
  List<TranslationTaskChunk> translationTaskChunks;
  String? translationErrorMessage;
  DateTime? translationCreatedAt;
  DateTime? translationUpdatedAt;

  // --- [新增] 图生视频任务字段 ---
  @JsonKey(defaultValue: TaskStatus.notStarted)
  TaskStatus videoGenerationStatus;
  @JsonKey(defaultValue: [])
  List<VideoGenerationTaskChunk> videoGenerationTaskChunks;
  String? videoGenerationErrorMessage;
  DateTime? videoGenerationCreatedAt;
  DateTime? videoGenerationUpdatedAt;

  BookshelfEntry({
    required this.id,
    required this.title,
    required this.originalPath,
    required this.fileType,
    required this.subCachePath,
    this.coverImagePath, // 添加到构造函数
    // 插图任务
    this.status = TaskStatus.notStarted,
    this.taskChunks = const [],
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
    // 翻译任务
    this.translationStatus = TaskStatus.notStarted,
    this.translationTaskChunks = const [],
    this.translationErrorMessage,
    this.translationCreatedAt,
    this.translationUpdatedAt,
    // [新增] 视频任务
    this.videoGenerationStatus = TaskStatus.notStarted,
    this.videoGenerationTaskChunks = const [],
    this.videoGenerationErrorMessage,
    this.videoGenerationCreatedAt,
    this.videoGenerationUpdatedAt,
  });

  //  插图进度
  double get illustrationProgress {
    if (taskChunks.isEmpty) {
      return status == TaskStatus.completed ? 1.0 : 0.0;
    }
    final completedCount = taskChunks.where((c) => c.status == ChunkStatus.completed).length;
    // 避免除以零
    if (taskChunks.isEmpty) return 0.0;
    return completedCount / taskChunks.length;
  }

  // 翻译进度
  double get translationProgress {
    if (translationTaskChunks.isEmpty) {
      return translationStatus == TaskStatus.completed ? 1.0 : 0.0;
    }
    final completedCount = translationTaskChunks.where((c) => c.status == ChunkStatus.completed).length;
    if (translationTaskChunks.isEmpty) return 0.0;
    return completedCount / translationTaskChunks.length;
  }

  // 视频生成进度
  double get videoGenerationProgress {
    if (videoGenerationTaskChunks.isEmpty) {
      return videoGenerationStatus == TaskStatus.completed ? 1.0 : 0.0;
    }
    final completedCount = videoGenerationTaskChunks
        .where((c) => c.status == ChunkStatus.completed)
        .length;
    if (videoGenerationTaskChunks.isEmpty) return 0.0;
    return completedCount / videoGenerationTaskChunks.length;
  }

  // copyWith 方法便于状态更新
  BookshelfEntry copyWith({
    String? coverImagePath,
    TaskStatus? status,
    List<IllustrationTaskChunk>? taskChunks,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? createdAt,
    DateTime? updatedAt,

    TaskStatus? translationStatus,
    List<TranslationTaskChunk>? translationTaskChunks,
    String? translationErrorMessage,
    bool clearTranslationErrorMessage = false,
    DateTime? translationCreatedAt,
    DateTime? translationUpdatedAt,

    TaskStatus? videoGenerationStatus,
    List<VideoGenerationTaskChunk>? videoGenerationTaskChunks,
    String? videoGenerationErrorMessage,
    bool clearVideoGenerationErrorMessage = false,
    DateTime? videoGenerationCreatedAt,
    DateTime? videoGenerationUpdatedAt,
  }) {
    return BookshelfEntry(
      id: id,
      title: title,
      originalPath: originalPath,
      fileType: fileType,
      subCachePath: subCachePath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      // 插图
      status: status ?? this.status,
      taskChunks: taskChunks ?? this.taskChunks,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      // 翻译
      translationStatus: translationStatus ?? this.translationStatus,
      translationTaskChunks: translationTaskChunks ?? this.translationTaskChunks,
      translationErrorMessage: clearTranslationErrorMessage ? null : (translationErrorMessage ?? this.translationErrorMessage),
      translationCreatedAt: translationCreatedAt ?? this.translationCreatedAt,
      translationUpdatedAt: translationUpdatedAt ?? DateTime.now(),
      // 视频
      videoGenerationStatus: videoGenerationStatus ?? this.videoGenerationStatus,
      videoGenerationTaskChunks: videoGenerationTaskChunks ?? this.videoGenerationTaskChunks,
      videoGenerationErrorMessage: clearVideoGenerationErrorMessage ? null : (videoGenerationErrorMessage ?? this.videoGenerationErrorMessage),
      videoGenerationCreatedAt: videoGenerationCreatedAt ?? this.videoGenerationCreatedAt,
      videoGenerationUpdatedAt: videoGenerationUpdatedAt ?? DateTime.now(),
    );
  }

  factory BookshelfEntry.fromJson(Map<String, dynamic> json) => _$BookshelfEntryFromJson(json);
  Map<String, dynamic> toJson() => _$BookshelfEntryToJson(this);
}