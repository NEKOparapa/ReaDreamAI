// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LineStructure _$LineStructureFromJson(Map<String, dynamic> json) =>
    LineStructure(
      id: (json['id'] as num).toInt(),
      text: json['text'] as String,
      sourceInfo: json['sourceInfo'] as String,
      originalContent: json['originalContent'] as String,
      illustrationPaths:
          (json['illustrationPaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      videoPaths:
          (json['videoPaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      sceneDescription: json['sceneDescription'] as String?,
      translatedText: json['translatedText'] as String?,
    );

Map<String, dynamic> _$LineStructureToJson(LineStructure instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'sourceInfo': instance.sourceInfo,
      'originalContent': instance.originalContent,
      'illustrationPaths': instance.illustrationPaths,
      'videoPaths': instance.videoPaths,
      'sceneDescription': instance.sceneDescription,
      'translatedText': instance.translatedText,
    };

ChapterStructure _$ChapterStructureFromJson(Map<String, dynamic> json) =>
    ChapterStructure(
      id: json['id'] as String,
      title: json['title'] as String,
      sourceFile: json['sourceFile'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => LineStructure.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ChapterStructureToJson(ChapterStructure instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'sourceFile': instance.sourceFile,
      'lines': instance.lines.map((e) => e.toJson()).toList(),
    };

Book _$BookFromJson(Map<String, dynamic> json) => Book(
  id: json['id'] as String,
  title: json['title'] as String,
  fileType: json['fileType'] as String,
  originalPath: json['originalPath'] as String,
  cachedPath: json['cachedPath'] as String,
  coverImagePath: json['coverImagePath'] as String?,
  chapters: (json['chapters'] as List<dynamic>)
      .map((e) => ChapterStructure.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$BookToJson(Book instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'fileType': instance.fileType,
  'originalPath': instance.originalPath,
  'cachedPath': instance.cachedPath,
  'coverImagePath': instance.coverImagePath,
  'chapters': instance.chapters.map((e) => e.toJson()).toList(),
};
