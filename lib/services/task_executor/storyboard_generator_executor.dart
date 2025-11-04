// lib/services/task_executor/storyboard_generator_executor.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:pool/pool.dart';

import '../../base/config_service.dart';
import '../../base/log/log_service.dart';
import '../../models/book.dart';
import '../../models/character_card_model.dart';
import '../../services/llm_service/llm_service.dart';
import '../../services/drawing_service/drawing_service.dart';
import '../../services/video_service/video_service.dart';
import '../../ui/bookshelf/novel_to_short_drama/novel_to_short_drama_workbench_page.dart'
    show ChapterScript, Scene, Shot;



// ==================== 内部辅助类 ====================

/// 场景任务封装
class _SceneTask {
  final String chapterTitle;
  final Scene scene;

  _SceneTask({
    required this.chapterTitle,
    required this.scene,
  });
}

/// 分镜任务封装
class _ShotTask {
  final String chapterTitle;
  final String sceneTitle;
  final Shot shot;

  _ShotTask({
    required this.chapterTitle,
    required this.sceneTitle,
    required this.shot,
  });
}
// 定义返回类型
typedef StoryboardGenerationResult = ({
  List<ChapterScript> script,
  List<CharacterCard> characters
});

// [MODIFIED] 定义返回类型，增加mainCharacter
typedef ScenePromptsResult = Map<int, ({String imagePrompt, String videoPrompt, String mainCharacter})>;

// [新增] 单个分镜提示词的返回类型
typedef SingleShotPromptsResult = ({String imagePrompt, String videoPrompt, String mainCharacter});


class StoryboardGeneratorExecutor {
  StoryboardGeneratorExecutor._();
  static final StoryboardGeneratorExecutor instance = StoryboardGeneratorExecutor._();

  final ConfigService _configService = ConfigService();
  final LlmService _llmService = LlmService.instance;
  final LogService _logger = LogService.instance;

  // ==================== 任务1: 生成分镜脚本 ====================
  
  Future<StoryboardGenerationResult> generateStoryboard({
    required Book book,
    required String requirements,
    required List<CharacterCard> characters,
    int? scenesPerChapter,
    int? shotsPerScene,
  }) async {
    _logger.info("开始为《${book.title}》生成分镜脚本...");

    final llmApi = _configService.getActiveLanguageApi();
    final llmConcurrency = llmApi.concurrencyLimit ?? 3;
    final llmRateLimiter = _configService.getRateLimiterForApi(llmApi);
    final pool = Pool(llmConcurrency);
    const maxRetries = 3;
    _logger.info("启动分镜脚本生成任务池，最大并发数: $llmConcurrency (API: ${llmApi.name})");

    final results = <(int, Map<String, dynamic>)>[];

    try {
      await Future.wait(
        book.chapters.asMap().entries.map((entry) {
          final chapterIndex = entry.key;
          final chapter = entry.value;

          return pool.withResource(() async {
            for (int attempt = 1; attempt <= maxRetries; attempt++) {
              try {
                _logger.info("正在处理章节 ${chapter.title}... (尝试 $attempt/$maxRetries)");
                await llmRateLimiter.acquire();
                _logger.info("章节 ${chapter.title} 已获取速率令牌，开始请求LLM。");

                final chapterText = chapter.lines.map((l) => l.text).join('\n');
                final (systemPrompt, messages) = _buildPromptForStoryboardGeneration(
                  novelTitle: book.title,
                  chapterTitle: chapter.title,
                  chapterText: chapterText,
                  requirements: requirements,
                  characters: characters,
                  scenesPerChapter: scenesPerChapter,
                  shotsPerScene: shotsPerScene,
                );

                final llmResponse = await _llmService.requestCompletion(
                  systemPrompt: systemPrompt,
                  messages: messages,
                  apiConfig: llmApi,
                );

                String jsonString = llmResponse;
                final match = RegExp(r'```json\s*([\s\S]+?)\s*```').firstMatch(llmResponse);
                if (match != null) jsonString = match.group(1)!;

                final Map<String, dynamic> responseJson = jsonDecode(jsonString);
                results.add((chapterIndex, responseJson));
                _logger.success("章节 ${chapter.title} 处理成功。");
                break;
              } catch (e, s) {
                _logger.error("处理章节 ${chapter.title} 失败 (尝试 $attempt/$maxRetries)", e, s);
                if (attempt == maxRetries) {
                  _logger.error("章节 ${chapter.title} 达到最大重试次数，将使用空结果。");
                  results.add((chapterIndex, {'script': [], 'characters': []}));
                }
                await Future.delayed(Duration(seconds: 2 * attempt));
              }
            }
          });
        }),
      );

      results.sort((a, b) => a.$1.compareTo(b.$1));

      final finalScript = <ChapterScript>[];
      final allGeneratedCharacters = <CharacterCard>[];

      for (int i = 0; i < book.chapters.length; i++) {
        final chapter = book.chapters[i];
        final chapterResult = results.firstWhere((r) => r.$1 == i, orElse: () => (i, {})).$2;

        final scenesJson = chapterResult['script'] as List<dynamic>? ?? [];
        final chapterScript = ChapterScript.fromJson({
          'originalChapterTitle': chapter.title,
          'scenes': scenesJson,
        });
        finalScript.add(chapterScript);

        if (characters.isEmpty) {
          final charactersJson = chapterResult['characters'] as List<dynamic>? ?? [];
          for (final charJson in charactersJson) {
            try {
              allGeneratedCharacters.add(CharacterCard.fromJson(charJson));
            } catch (e) {
              _logger.warn("解析AI生成的角色卡失败: $charJson, 错误: $e");
            }
          }
        }
      }

      final uniqueCharacters = _deduplicateCharacters(allGeneratedCharacters);
      _logger.success("所有章节分镜脚本生成完毕！");
      return (script: finalScript, characters: uniqueCharacters);
    } catch (e, s) {
      _logger.error("生成分镜脚本时发生严重错误", e, s);
      rethrow;
    }
  }

  // ==================== 任务2: 批量生成提示词（按场景并发）====================
  
  /// 为整个脚本的所有场景生成提示词（按场景为单位并发）
  Future<void> generateAllPromptsForScript({
    required String novelTitle,
    required List<CharacterCard> characters,
    required List<ChapterScript> script,
    required void Function(double progress, String status) onProgress,
  }) async {
    _logger.info("🚀 开始为《$novelTitle》生成所有场景的提示词...");

    // 1. 收集所有场景作为子任务
    final allSceneTasks = <_SceneTask>[];
    for (final chapter in script) {
      for (final scene in chapter.scenes) {
        if (scene.shots.isNotEmpty) {
          allSceneTasks.add(_SceneTask(
            chapterTitle: chapter.originalChapterTitle,
            scene: scene,
          ));
        }
      }
    }

    if (allSceneTasks.isEmpty) {
      _logger.warn("没有可用的场景，跳过提示词生成。");
      onProgress(1.0, '无场景需要处理');
      return;
    }

    _logger.info("📦 发现 ${allSceneTasks.length} 个场景需要生成提示词");

    // 2. 获取并发配置
    final llmApi = _configService.getActiveLanguageApi();
    final llmConcurrency = llmApi.concurrencyLimit ?? 3;
    final llmRateLimiter = _configService.getRateLimiterForApi(llmApi);
    final pool = Pool(llmConcurrency);
    const maxRetries = 3;

    _logger.info("🛠️ 启动提示词生成任务池，最大并发数: $llmConcurrency (API: ${llmApi.name})");

    int processedCount = 0;
    final totalScenes = allSceneTasks.length;

    try {
      // 3. 并发处理所有场景
      final tasks = allSceneTasks.map((sceneTask) {
        return pool.withResource(() async {
          for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
              await llmRateLimiter.acquire();
              _logger.info("  ⚡️ 正在为场景「${sceneTask.scene.titleController.text}」生成提示词 (尝试 $attempt/$maxRetries)");

              // 调用单个场景的提示词生成方法
              final prompts = await _generatePromptsForScene(
                novelTitle: novelTitle,
                characters: characters,
                chapterTitle: sceneTask.chapterTitle,
                scene: sceneTask.scene,
                apiConfig: llmApi,
              );

              // [MODIFIED] 更新场景中所有分镜的提示词和主要角色
              for (final shot in sceneTask.scene.shots) {
                if (prompts.containsKey(shot.shotNumber)) {
                  shot.firstFramePromptController.text = prompts[shot.shotNumber]!.imagePrompt;
                  shot.videoPromptController.text = prompts[shot.shotNumber]!.videoPrompt;
                  shot.mainCharacterController.text = prompts[shot.shotNumber]!.mainCharacter;
                }
              }

              _logger.success("  ✅ 场景「${sceneTask.scene.titleController.text}」提示词生成成功 (${prompts.length} 个分镜)");
              break; // 成功，跳出重试循环
            } catch (e, s) {
              _logger.error("  ❌ 场景「${sceneTask.scene.titleController.text}」提示词生成失败 (尝试 $attempt/$maxRetries)", e, s);
              if (attempt == maxRetries) {
                _logger.error("  ⚠️ 场景「${sceneTask.scene.titleController.text}」达到最大重试次数，跳过。");
              }
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }

          // 更新进度
          processedCount++;
          onProgress(
            processedCount / totalScenes,
            '正在生成提示词: $processedCount / $totalScenes',
          );
        });
      });

      await Future.wait(tasks);
      _logger.success("🎉 所有场景的提示词生成完毕！");
    } catch (e, s) {
      _logger.error("❌ 批量生成提示词时发生错误", e, s);
      rethrow;
    }
  }

  /// 为单个场景的所有分镜生成提示词（内部方法）
  Future<ScenePromptsResult> _generatePromptsForScene({
    required String novelTitle,
    required List<CharacterCard> characters,
    required String chapterTitle,
    required Scene scene,
    required dynamic apiConfig,
  }) async {
    final (systemPrompt, messages) = _buildPromptForScenePrompts(
      novelTitle: novelTitle,
      characters: characters,
      chapterTitle: chapterTitle,
      sceneTitle: scene.titleController.text,
      shots: scene.shots,
    );

    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: messages,
      apiConfig: apiConfig,
    );

    try {
      String jsonString = llmResponse;
      final match = RegExp(r'```json\s*([\s\S]+?)\s*```').firstMatch(llmResponse);
      if (match != null) jsonString = match.group(1)!;

      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final shotsArray = data['shots'] as List<dynamic>? ?? [];

      // [MODIFIED] 更新返回类型和解析逻辑
      final result = <int, ({String imagePrompt, String videoPrompt, String mainCharacter})>{};
      for (final shotData in shotsArray) {
        final shotNumber = shotData['shotNumber'] as int?;
        final imagePrompt = shotData['image_prompt'] as String? ?? '';
        final videoPrompt = shotData['video_prompt'] as String? ?? '';
        final mainCharacter = shotData['main_character'] as String? ?? '';

        if (shotNumber != null) {
          result[shotNumber] = (imagePrompt: imagePrompt, videoPrompt: videoPrompt, mainCharacter: mainCharacter);
        }
      }

      return result;
    } catch (e, s) {
      _logger.error("解析场景提示词响应失败", e, s);
      return {};
    }
  }

  // ==================== [新增] 任务2.1: 为单个分镜生成提示词 ====================
  Future<SingleShotPromptsResult> generatePromptsForSingleShot({
    required String novelTitle,
    required List<CharacterCard> characters,
    required String chapterTitle,
    required String sceneTitle,
    required Shot shot,
  }) async {
    _logger.info("⚡️ 正在为分镜 ${shot.shotNumber}「${shot.contentController.text.substring(0, min(10, shot.contentController.text.length))}...」生成提示词");
    final llmApi = _configService.getActiveLanguageApi();

    // 复用为场景生成提示词的Prompt构建逻辑，但只传入单个分镜
    final (systemPrompt, messages) = _buildPromptForScenePrompts(
      novelTitle: novelTitle,
      characters: characters,
      chapterTitle: chapterTitle,
      sceneTitle: sceneTitle,
      shots: [shot], // 关键：只传入当前这一个分镜
    );

    final llmResponse = await _llmService.requestCompletion(
      systemPrompt: systemPrompt,
      messages: messages,
      apiConfig: llmApi,
    );

    try {
      String jsonString = llmResponse;
      final match = RegExp(r'```json\s*([\s\S]+?)\s*```').firstMatch(llmResponse);
      if (match != null) jsonString = match.group(1)!;

      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final shotsArray = data['shots'] as List<dynamic>? ?? [];

      if (shotsArray.isNotEmpty) {
        final shotData = shotsArray.first;
        final imagePrompt = shotData['image_prompt'] as String? ?? '';
        final videoPrompt = shotData['video_prompt'] as String? ?? '';
        final mainCharacter = shotData['main_character'] as String? ?? '';
        _logger.success("✅ 分镜 ${shot.shotNumber} 提示词生成成功");
        return (imagePrompt: imagePrompt, videoPrompt: videoPrompt, mainCharacter: mainCharacter);
      } else {
        throw Exception("LLM响应中未包含分镜数据");
      }
    } catch (e, s) {
      _logger.error("❌ 解析单个分镜提示词响应失败", e, s);
      rethrow;
    }
  }

  // ==================== 任务3: 批量生成媒体（图片+视频）====================
  
  /// 为整个脚本的所有分镜生成媒体文件
  // [MODIFIED] 更新方法签名以接收角色列表
  Future<void> generateAllMediaForScript({
    required Book book,
    required List<ChapterScript> script,
    required List<CharacterCard> characters,
    required void Function(double progress, String status) onProgress,
  }) async {
    _logger.info("🚀 开始为《${book.title}》生成所有分镜的媒体文件...");

    // 1. 收集所有分镜
    final allShots = <_ShotTask>[];
    for (final chapter in script) {
      for (final scene in chapter.scenes) {
        for (final shot in scene.shots) {
          if (shot.firstFramePromptController.text.isNotEmpty) {
            allShots.add(_ShotTask(
              chapterTitle: chapter.originalChapterTitle,
              sceneTitle: scene.titleController.text,
              shot: shot,
            ));
          }
        }
      }
    }

    if (allShots.isEmpty) {
      _logger.warn("没有可生成的分镜，跳过媒体生成。");
      onProgress(1.0, '无分镜需要处理');
      return;
    }

    _logger.info("📦 发现 ${allShots.length} 个分镜需要生成媒体");

    // 2. 获取API配置和并发限制
    final drawingApi = _configService.getActiveDrawingApi();
    final videoApi = _configService.getActiveVideoApi();

    final drawConcurrency = drawingApi.concurrencyLimit ?? 1;
    final videoConcurrency = videoApi.concurrencyLimit ?? 1;
    final concurrency = min(drawConcurrency, videoConcurrency);

    final drawRateLimiter = _configService.getRateLimiterForApi(drawingApi);
    final videoRateLimiter = _configService.getRateLimiterForApi(videoApi);

    final pool = Pool(max(1, concurrency));
    const maxRetries = 3;
    _logger.info("🛠️ 启动媒体生成任务池，最大并发数: $concurrency");

    // 3. 获取媒体生成参数
    final imageSizeString = _configService.getSetting<String>('image_gen_size', '1024*1024');
    final parts = imageSizeString.split('*');
    final width = parts.length == 2 ? int.tryParse(parts[0]) ?? 1024 : 1024;
    final height = parts.length == 2 ? int.tryParse(parts[1]) ?? 1024 : 1024;
    final videoDuration = _configService.getSetting<int>('video_gen_duration', 5);
    final videoResolution = _configService.getSetting<String>('video_gen_resolution', '720p');

    // 4. 准备保存目录 (修改后：使用Workbench目录)
    final workbenchDirs = await _configService.getOrCreateWorkbenchDirs();
    final imageSaveDir = workbenchDirs['image']!; // 获取 .../Config/Workbench/Image 目录
    final videoSaveDir = workbenchDirs['video']!; // 获取 .../Config/Workbench/video 目录

    int processedCount = 0;
    final totalShots = allShots.length;

    try {
      // 5. 并发处理所有分镜
      final tasks = allShots.map((shotTask) {
        return pool.withResource(() async {
          String? generatedImagePath;

          // 5.1 生成图片（带重试）
          for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
              await drawRateLimiter.acquire();
              _logger.info("  🎨 正在为分镜 ${shotTask.shot.shotNumber} 生成图片 (尝试 $attempt/$maxRetries)");
              
              // --- [MODIFIED] 新增逻辑: 查找角色参考图 ---
              String? referenceImagePath;
              final mainCharName = shotTask.shot.mainCharacterController.text;
              if (mainCharName.isNotEmpty) {
                try {
                  final matchingChar = characters.firstWhere(
                    (c) => c.characterName == mainCharName,
                  );
                  // 优先使用本地路径
                  referenceImagePath = matchingChar.referenceImagePath ?? matchingChar.referenceImageUrl;
                  if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
                     _logger.info("  👤 找到主体角色 '$mainCharName' 的参考图: $referenceImagePath");
                  }
                } catch (e) {
                  _logger.warn("  ⚠️ 未能为 '$mainCharName' 找到匹配的角色卡或参考图。");
                }
              }
              // --- 结束新增逻辑 ---

              final imagePaths = await DrawingService.instance.generateImages(
                positivePrompt: shotTask.shot.firstFramePromptController.text,
                negativePrompt: _configService.getActiveTagContent(
                  'drawing_negative_tags',
                  'active_drawing_negative_tag_id',
                ),
                saveDir: imageSaveDir.path,
                count: 1,
                width: width,
                height: height,
                apiConfig: drawingApi,
                // 新增: 传入参考图路径
                referenceImagePath: referenceImagePath,
              );

              if (imagePaths != null && imagePaths.isNotEmpty) {
                generatedImagePath = imagePaths.first;
                shotTask.shot.firstFrameImagePaths.addAll(imagePaths);
                _logger.success("  ✅ 分镜 ${shotTask.shot.shotNumber} 图片生成成功");
                break;
              }
            } catch (e, s) {
              _logger.error("  ❌ 分镜 ${shotTask.shot.shotNumber} 图片生成失败 (尝试 $attempt/$maxRetries)", e, s);
              if (attempt == maxRetries) {
                _logger.error("  ⚠️ 分镜 ${shotTask.shot.shotNumber} 图片达到最大重试次数");
              }
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }

          // 5.2 如果图片生成成功且有视频提示词，则生成视频（带重试）
          if (generatedImagePath != null && shotTask.shot.videoPromptController.text.isNotEmpty) {
            for (int attempt = 1; attempt <= maxRetries; attempt++) {
              try {
                await videoRateLimiter.acquire();
                _logger.info("  🎬 正在为分镜 ${shotTask.shot.shotNumber} 生成视频 (尝试 $attempt/$maxRetries)");

                final videoPaths = await VideoService.instance.generateVideo(
                  positivePrompt: shotTask.shot.videoPromptController.text,
                  saveDir: videoSaveDir.path,
                  count: 1,
                  referenceImagePath: generatedImagePath,
                  duration: videoDuration,
                  resolution: videoResolution,
                  apiConfig: videoApi,
                );

                if (videoPaths != null && videoPaths.isNotEmpty) {
                  shotTask.shot.videoPaths.addAll(videoPaths);
                  _logger.success("  ✅ 分镜 ${shotTask.shot.shotNumber} 视频生成成功");
                  break;
                }
              } catch (e, s) {
                _logger.error("  ❌ 分镜 ${shotTask.shot.shotNumber} 视频生成失败 (尝试 $attempt/$maxRetries)", e, s);
                if (attempt == maxRetries) {
                  _logger.error("  ⚠️ 分镜 ${shotTask.shot.shotNumber} 视频达到最大重试次数");
                }
                await Future.delayed(Duration(seconds: 2 * attempt));
              }
            }
          }

          // 5.3 更新进度
          processedCount++;
          onProgress(
            processedCount / totalShots,
            '正在生成媒体: $processedCount / $totalShots',
          );
        });
      });

      await Future.wait(tasks);
      _logger.success("🎉 所有分镜的媒体生成完毕！");
    } catch (e, s) {
      _logger.error("❌ 批量生成媒体时发生错误", e, s);
      rethrow;
    }
  }

  // ==================== [新增] 任务3.1: 为单个分镜生成首帧图片 ====================
  Future<String> generateImageForShot({
    required Shot shot,
    required List<CharacterCard> characters,
  }) async {
    _logger.info("🎨 正在为分镜 ${shot.shotNumber} 生成图片...");
    if (shot.firstFramePromptController.text.isEmpty) {
      throw Exception("首帧图像提示词为空，无法生成图片。");
    }

    final drawingApi = _configService.getActiveDrawingApi();
    final imageSizeString = _configService.getSetting<String>('image_gen_size', '1024*1024');
    final parts = imageSizeString.split('*');
    final width = int.tryParse(parts[0]) ?? 1024;
    final height = int.tryParse(parts[1]) ?? 1024;
    final workbenchDirs = await _configService.getOrCreateWorkbenchDirs();
    final imageSaveDir = workbenchDirs['image']!;

    // --- 查找角色参考图 ---
    String? referenceImagePath;
    final mainCharName = shot.mainCharacterController.text;
    if (mainCharName.isNotEmpty) {
      try {
        final matchingChar = characters.firstWhere((c) => c.characterName == mainCharName);
        referenceImagePath = matchingChar.referenceImagePath ?? matchingChar.referenceImageUrl;
        if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
           _logger.info("👤 找到主体角色 '$mainCharName' 的参考图: $referenceImagePath");
        }
      } catch (e) {
        _logger.warn("⚠️ 未能为 '$mainCharName' 找到匹配的角色卡或参考图。");
      }
    }

    final imagePaths = await DrawingService.instance.generateImages(
      positivePrompt: shot.firstFramePromptController.text,
      negativePrompt: _configService.getActiveTagContent(
        'drawing_negative_tags',
        'active_drawing_negative_tag_id',
      ),
      saveDir: imageSaveDir.path,
      count: 1,
      width: width,
      height: height,
      apiConfig: drawingApi,
      referenceImagePath: referenceImagePath,
    );

    if (imagePaths != null && imagePaths.isNotEmpty) {
      _logger.success("✅ 分镜 ${shot.shotNumber} 图片生成成功: ${imagePaths.first}");
      return imagePaths.first;
    } else {
      throw Exception("绘画服务未能返回任何图片路径。");
    }
  }

  // ==================== [新增] 任务3.2: 为单个分镜生成视频 ====================
  Future<String> generateVideoForShot({ required Shot shot }) async {
     _logger.info("🎬 正在为分镜 ${shot.shotNumber} 生成视频...");
    if (shot.videoPromptController.text.isEmpty) {
      throw Exception("视频提示词为空，无法生成视频。");
    }
    if (shot.firstFrameImagePaths.isEmpty || !await File(shot.firstFrameImagePaths.first).exists()) {
      throw Exception("缺少有效的首帧图片，无法生成视频。");
    }

    final videoApi = _configService.getActiveVideoApi();
    final videoDuration = _configService.getSetting<int>('video_gen_duration', 5);
    final videoResolution = _configService.getSetting<String>('video_gen_resolution', '720p');
    final workbenchDirs = await _configService.getOrCreateWorkbenchDirs();
    final videoSaveDir = workbenchDirs['video']!;
    final referenceImagePath = shot.firstFrameImagePaths.first;

    final videoPaths = await VideoService.instance.generateVideo(
      positivePrompt: shot.videoPromptController.text,
      saveDir: videoSaveDir.path,
      count: 1,
      referenceImagePath: referenceImagePath,
      duration: videoDuration,
      resolution: videoResolution,
      apiConfig: videoApi,
    );

    if (videoPaths != null && videoPaths.isNotEmpty) {
      _logger.success("✅ 分镜 ${shot.shotNumber} 视频生成成功: ${videoPaths.first}");
      return videoPaths.first;
    } else {
      throw Exception("视频服务未能返回任何视频路径。");
    }
  }

  // ==================== 私有方法: 提示词构建逻辑 ====================

  /// 生成分镜脚本提示词
  (String, List<Map<String, String>>) _buildPromptForStoryboardGeneration({
    required String novelTitle,
    required String chapterTitle,
    required String chapterText,
    required String requirements,
    required List<CharacterCard> characters,
    int? scenesPerChapter,
    int? shotsPerScene,
  }) {
    String characterInfoBlock = '';
    if (characters.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 主要角色信息 (请基于此信息进行创作):');
      for (final char in characters) {
        buffer.writeln('- 角色名: ${char.characterName}');
        if (char.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${char.appearance}');
        if (char.clothing.isNotEmpty) buffer.writeln('  - 服装: ${char.clothing}');
        if (char.personality.isNotEmpty) buffer.writeln('  - 性格: ${char.personality}');
      }
      characterInfoBlock = buffer.toString();
    }

    const String systemPrompt = """你是一个专业的影视编剧和角色设计师。你的任务是将提供的小说章节内容,根据用户要求,改编成详细的分镜脚本。

任务要求:
1. 场景划分: 将章节内容合理地划分为多个场景(Scene)。每个场景的标题title字段应清晰地概括场景内容,并在标题中包含时间和地点(例如:"场景1 日/外景 - 森林边缘")。
2. 分镜设计: 在每个场景内,设计一系列分镜(Shot)。每个分镜都需要包含以下元素:
   - 景别(shotType): 如全景、中景、近景、特写等
   - 运镜(cameraMove): 如固定、推、拉、摇、跟等
   - 登场角色(characters): 此分镜中出现的角色名
   - 画面内容(content): 详细描述画面中发生的事情、人物的动作和表情
   - 声音/对白(sound): 包含角色的对白、旁白或重要的环境音效
   - 分镜时长(duration): 预估的时长,如"3s","5s"
3. 忠于原作: 改编应在尊重小说原意的基础上进行,保留关键情节和对话。
4. 遵循要求: 严格遵守用户提供的额外"分镜要求"和"结构要求"。
5. 角色生成:
   - 如果用户提供了"主要角色信息": 你必须严格参考这些信息来创作分镜,并且在返回的characters数组中返回一个空数组[]
   - 如果用户没有提供"主要角色信息": 你需要根据本章节内容,分析并识别出登场的主要角色,为他们创建角色简介,然后将这些角色信息填充到返回的characters数组中

输出格式: 请严格以JSON格式返回一个根对象,该对象包含script和characters两个键。
{
  "script": [
    {
      "title": "场景1 日/外景 - 森林边缘",
      "shots": [
        {
          "shotNumber": 1,
          "shotType": "全景",
          "cameraMove": "固定",
          "characters": "主角A",
          "content": "广阔的森林边缘,主角A从树林中走出,显得疲惫不堪。",
          "sound": "风声,鸟鸣声。",
          "duration": "4s"
        }
      ]
    }
  ],
  "characters": []
}""";

    String finalRequirements = requirements;
    final structureConstraints = StringBuffer();
    if (scenesPerChapter != null) {
      structureConstraints.writeln('- 请为本章节生成大约 $scenesPerChapter 个场景。');
    }
    if (shotsPerScene != null) {
      structureConstraints.writeln('- 请为每个场景生成大约 $shotsPerScene 个分镜。');
    }

    if (structureConstraints.isNotEmpty) {
      finalRequirements = '$finalRequirements\n\n### 结构要求:\n${structureConstraints.toString()}';
    }

    final realUserPrompt = """
小说标题: 《$novelTitle》
章节标题: 《$chapterTitle》
分镜要求: ${finalRequirements.isNotEmpty ? finalRequirements : "无特殊要求,请按专业标准生成。"}

$characterInfoBlock

章节原文:
$chapterText

请根据以上信息,为本章节生成分镜脚本和角色信息。
""";

    final messages = [
      {'role': 'user', 'content': realUserPrompt},
    ];
    return (systemPrompt, messages);
  }

  /// [MODIFIED] 生成首帧图片与视频的提示词
  (String, List<Map<String, String>>) _buildPromptForScenePrompts({
    required String novelTitle,
    required List<CharacterCard> characters,
    required String chapterTitle,
    required String sceneTitle,
    required List<Shot> shots,
  }) {
    // 构建角色信息块
    String characterInfoBlock = '';
    if (characters.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('### 主要角色信息 (characterName 字段是匹配的关键):');
      for (final char in characters) {
        buffer.writeln('- 角色名 (characterName): ${char.characterName}');
        if (char.appearance.isNotEmpty) buffer.writeln('  - 外貌: ${char.appearance}');
        if (char.clothing.isNotEmpty) buffer.writeln('  - 服装: ${char.clothing}');
        if (char.personality.isNotEmpty) buffer.writeln('  - 性格: ${char.personality}');
        if (char.other.isNotEmpty) buffer.writeln('  - 其他: ${char.other}');
      }
      characterInfoBlock = buffer.toString();
    }

    // 构建所有分镜的信息
    final buffer = StringBuffer();
    buffer.writeln('### 该场景的所有分镜:');
    for (final shot in shots) {
      buffer.writeln('分镜 ${shot.shotNumber}:');
      buffer.writeln('  - 景别: ${shot.shotTypeController.text}');
      buffer.writeln('  - 运镜: ${shot.cameraMoveController.text}');
      buffer.writeln('  - 登场角色: ${shot.charactersController.text}');
      buffer.writeln('  - 画面内容: ${shot.contentController.text}');
      buffer.writeln('  - 声音/对白: ${shot.soundController.text}');
      buffer.writeln('  - 时长: ${shot.durationController.text}');
      buffer.writeln('');
    }
    final shotsInfoBlock = buffer.toString();

    const String systemPrompt = """你是一个AI绘画和视频生成的提示词专家。你的任务是根据提供的场景信息和该场景下所有分镜的详细内容,为每个分镜生成:
1. 首帧图片提示词(image_prompt)
2. 视频提示词(video_prompt)
3. 主体角色名(main_character)

要求:

【主体角色名 (main_character)】
- 分析"登场角色"和"画面内容"字段,判断该分镜是否主要聚焦于某一个角色。
- 如果是,则从上方提供的"主要角色信息"列表中,找到最匹配的角色,并将其`characterName`字段的**完整内容**填入此字段。
- 如果画面是多人场景、远景或没有明确的单一主体,则返回一个**空字符串** ""。

【首帧图片提示词 (image_prompt)】
- 详细、具体,描述一个静态画面。
- 包含主体、外貌、服装、姿态、情绪、构图、环境、光影等。
- 使用AI绘画标签化的语言(如: 1boy, solo, looking at viewer, silver armor, red cape...)。
- 不包含任何动态描述(如: running, walking, smiling)。
- 不包含任何风格或画质词(如: masterpiece, best quality, anime style)。
- 必须是纯英文,使用逗号分隔的标签格式。

【视频提示词 (video_prompt)】
- 简洁、有力,专注于描述动态。
- 描述画面中发生的核心运动或变化。
- 可以包含运镜描述(如: camera slowly zooms in)。
- 是对首帧图片的动态化延展。
- 必须是纯英文。

输出格式: 请严格以JSON格式返回,包含一个shots数组,数组中每个对象对应一个分镜:
{
  "shots": [
    {
      "shotNumber": 1,
      "main_character": "主角A",
      "image_prompt": "1boy, solo, short black hair, determined eyes, wearing silver armor, red cape, standing on a desolate battlefield, hand on sword hilt, rain, mud, stormy sky, dramatic lighting, full body shot",
      "video_prompt": "The knight slowly raises his shimmering sword, rain intensifies splashing on his armor, camera slowly pushes in on his determined face"
    },
    {
      "shotNumber": 2,
      "main_character": "",
      "image_prompt": "...",
      "video_prompt": "..."
    }
  ]
}""";

    final realUserPrompt = """
小说标题: 《$novelTitle》
章节标题: 《$chapterTitle》
场景标题: $sceneTitle

$characterInfoBlock

$shotsInfoBlock

请为以上场景中的每个分镜生成"首帧图片提示词", "视频提示词" 和 "主体角色名"。
注意:
1. 必须为所有${shots.length}个分镜都生成
2. shotNumber必须与分镜编号严格对应
3. 提示词必须是纯英文
4. main_character必须精确匹配提供的角色信息中的characterName, 否则返回空字符串
""";

    final messages = [
      {'role': 'user', 'content': realUserPrompt},
    ];
    return (systemPrompt, messages);
  }

  List<CharacterCard> _deduplicateCharacters(List<CharacterCard> characters) {
    final uniqueCharacters = <String, CharacterCard>{};
    for (final char in characters) {
      uniqueCharacters.putIfAbsent(char.characterName, () => char);
    }
    return uniqueCharacters.values.toList();
  }
}
