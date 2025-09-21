// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookshelf_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IllustrationTaskChunk _$IllustrationTaskChunkFromJson(
  Map<String, dynamic> json,
) => IllustrationTaskChunk(
  id: json['id'] as String,
  chapterId: json['chapterId'] as String,
  startLineId: (json['startLineId'] as num).toInt(),
  endLineId: (json['endLineId'] as num).toInt(),
  scenesToGenerate: (json['scenesToGenerate'] as num).toInt(),
  status:
      $enumDecodeNullable(_$ChunkStatusEnumMap, json['status']) ??
      ChunkStatus.pending,
);

Map<String, dynamic> _$IllustrationTaskChunkToJson(
  IllustrationTaskChunk instance,
) => <String, dynamic>{
  'id': instance.id,
  'chapterId': instance.chapterId,
  'startLineId': instance.startLineId,
  'endLineId': instance.endLineId,
  'scenesToGenerate': instance.scenesToGenerate,
  'status': _$ChunkStatusEnumMap[instance.status]!,
};

const _$ChunkStatusEnumMap = {
  ChunkStatus.pending: 'pending',
  ChunkStatus.running: 'running',
  ChunkStatus.completed: 'completed',
  ChunkStatus.failed: 'failed',
};

TranslationTaskChunk _$TranslationTaskChunkFromJson(
  Map<String, dynamic> json,
) => TranslationTaskChunk(
  id: json['id'] as String,
  chapterId: json['chapterId'] as String,
  startLineId: (json['startLineId'] as num).toInt(),
  endLineId: (json['endLineId'] as num).toInt(),
  status:
      $enumDecodeNullable(_$ChunkStatusEnumMap, json['status']) ??
      ChunkStatus.pending,
);

Map<String, dynamic> _$TranslationTaskChunkToJson(
  TranslationTaskChunk instance,
) => <String, dynamic>{
  'id': instance.id,
  'chapterId': instance.chapterId,
  'startLineId': instance.startLineId,
  'endLineId': instance.endLineId,
  'status': _$ChunkStatusEnumMap[instance.status]!,
};

BookshelfEntry _$BookshelfEntryFromJson(Map<String, dynamic> json) =>
    BookshelfEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      originalPath: json['originalPath'] as String,
      fileType: json['fileType'] as String,
      subCachePath: json['subCachePath'] as String,
      coverImagePath: json['coverImagePath'] as String?,
      status:
          $enumDecodeNullable(_$TaskStatusEnumMap, json['status']) ??
          TaskStatus.notStarted,
      taskChunks:
          (json['taskChunks'] as List<dynamic>?)
              ?.map(
                (e) =>
                    IllustrationTaskChunk.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      errorMessage: json['errorMessage'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      translationStatus:
          $enumDecodeNullable(_$TaskStatusEnumMap, json['translationStatus']) ??
          TaskStatus.notStarted,
      translationTaskChunks:
          (json['translationTaskChunks'] as List<dynamic>?)
              ?.map(
                (e) => TranslationTaskChunk.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      translationErrorMessage: json['translationErrorMessage'] as String?,
      translationCreatedAt: json['translationCreatedAt'] == null
          ? null
          : DateTime.parse(json['translationCreatedAt'] as String),
      translationUpdatedAt: json['translationUpdatedAt'] == null
          ? null
          : DateTime.parse(json['translationUpdatedAt'] as String),
    );

Map<String, dynamic> _$BookshelfEntryToJson(BookshelfEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'originalPath': instance.originalPath,
      'fileType': instance.fileType,
      'subCachePath': instance.subCachePath,
      'coverImagePath': instance.coverImagePath,
      'status': _$TaskStatusEnumMap[instance.status]!,
      'taskChunks': instance.taskChunks.map((e) => e.toJson()).toList(),
      'errorMessage': instance.errorMessage,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'translationStatus': _$TaskStatusEnumMap[instance.translationStatus]!,
      'translationTaskChunks': instance.translationTaskChunks
          .map((e) => e.toJson())
          .toList(),
      'translationErrorMessage': instance.translationErrorMessage,
      'translationCreatedAt': instance.translationCreatedAt?.toIso8601String(),
      'translationUpdatedAt': instance.translationUpdatedAt?.toIso8601String(),
    };

const _$TaskStatusEnumMap = {
  TaskStatus.notStarted: 'notStarted',
  TaskStatus.queued: 'queued',
  TaskStatus.running: 'running',
  TaskStatus.paused: 'paused',
  TaskStatus.completed: 'completed',
  TaskStatus.failed: 'failed',
  TaskStatus.canceled: 'canceled',
};
