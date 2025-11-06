// lib/models/storyboard_script_model.dart

import 'package:flutter/material.dart';

// 视频书模型，用于封装保存到书架的数据
class VideoBook {
  final String novelTitle;
  final List<ChapterScript> script;

  VideoBook({required this.novelTitle, required this.script});

  factory VideoBook.fromJson(Map<String, dynamic> json) {
    return VideoBook(
      novelTitle: json['novelTitle'] as String,
      script: (json['script'] as List<dynamic>)
          .map((e) => ChapterScript.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'novelTitle': novelTitle,
        'script': script.map((e) => e.toJson()).toList(),
      };
}

// ChapterScript 模型定义
class ChapterScript {
  int chapterNumber;
  final String originalChapterTitle;
  List<Scene> scenes;

  ChapterScript({required this.chapterNumber, required this.originalChapterTitle, List<Scene>? scenes})
      : scenes = scenes ?? [Scene(sceneNumber: 1)];

  void dispose() {
    for (final scene in scenes) {
      scene.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
        'chapterNumber': chapterNumber,
        'originalChapterTitle': originalChapterTitle,
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };

  factory ChapterScript.fromJson(Map<String, dynamic> json) {
    final scenesList = json['scenes'] as List<dynamic>? ?? [];
    return ChapterScript(
      chapterNumber: json['chapterNumber'] as int? ?? 1,
      originalChapterTitle: json['originalChapterTitle'] as String? ?? '未知章节',
      scenes: scenesList
          .map((s) => Scene.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

// Scene 模型定义
class Scene {
  int sceneNumber;
  TextEditingController titleController = TextEditingController(text: '场景');
  List<Shot> shots;

  Scene({required this.sceneNumber, List<Shot>? shots}) : shots = shots ?? [Shot(shotNumber: 1)];

  void dispose() {
    titleController.dispose();
    for (final shot in shots) {
      shot.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
        'sceneNumber': sceneNumber,
        'title': titleController.text,
        'shots': shots.map((s) => s.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final shotsList = json['shots'] as List<dynamic>? ?? [];
    final scene = Scene(
      sceneNumber: json['sceneNumber'] as int? ?? 1,
      shots: shotsList
          .map((s) => Shot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
    scene.titleController.text = json['title'] as String? ?? '场景';
    return scene;
  }
}

// Shot 模型定义
class Shot {
  int shotNumber;
  TextEditingController shotTypeController;
  TextEditingController cameraMoveController;
  TextEditingController charactersController;
  TextEditingController contentController;
  TextEditingController soundController;
  TextEditingController durationController;
  TextEditingController firstFramePromptController = TextEditingController();
  TextEditingController mainCharacterController = TextEditingController();
  List<String> firstFrameImagePaths = [];
  TextEditingController videoPromptController = TextEditingController();
  List<String> videoPaths = [];

  Shot({
    required this.shotNumber,
    String shotType = '全景',
    String cameraMove = '固定',
    String characters = '',
    String content = '',
    String sound = '',
    String duration = '3s',
  })  : shotTypeController = TextEditingController(text: shotType),
        cameraMoveController = TextEditingController(text: cameraMove),
        charactersController = TextEditingController(text: characters),
        contentController = TextEditingController(text: content),
        soundController = TextEditingController(text: sound),
        durationController = TextEditingController(text: duration);

  void dispose() {
    shotTypeController.dispose();
    cameraMoveController.dispose();
    charactersController.dispose();
    contentController.dispose();
    soundController.dispose();
    durationController.dispose();
    firstFramePromptController.dispose();
    mainCharacterController.dispose();
    videoPromptController.dispose();
  }

  Map<String, dynamic> toJson() => {
        'shotNumber': shotNumber,
        'shotType': shotTypeController.text,
        'cameraMove': cameraMoveController.text,
        'characters': charactersController.text,
        'content': contentController.text,
        'sound': soundController.text,
        'duration': durationController.text,
        'firstFramePrompt': firstFramePromptController.text,
        'mainCharacter': mainCharacterController.text,
        'firstFrameImagePaths': firstFrameImagePaths,
        'videoPrompt': videoPromptController.text,
        'videoPaths': videoPaths,
      };

  factory Shot.fromJson(Map<String, dynamic> json) {
    String parseField(dynamic fieldValue) {
      if (fieldValue == null) return '';
      if (fieldValue is List) return fieldValue.join(', ');
      return fieldValue.toString();
    }

    final shot = Shot(
      shotNumber: json['shotNumber'] as int? ?? 1,
      shotType: parseField(json['shotType']),
      cameraMove: parseField(json['cameraMove']),
      characters: parseField(json['characters']),
      content: parseField(json['content']),
      sound: parseField(json['sound']),
      duration: parseField(json['duration']),
    );

    shot.firstFramePromptController.text =
        json['firstFramePrompt'] as String? ?? '';
    shot.mainCharacterController.text = json['mainCharacter'] as String? ?? '';
    shot.firstFrameImagePaths =
        List<String>.from(json['firstFrameImagePaths'] ?? []);
    shot.videoPromptController.text = json['videoPrompt'] as String? ?? '';
    shot.videoPaths = List<String>.from(json['videoPaths'] ?? []);
    return shot;
  }
}