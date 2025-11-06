import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../base/log/log_service.dart';
import '../../models/bookshelf_entry.dart';
import '../../models/storyboard_script_model.dart';

/// 负责导出 videoBook 媒体资源的服务
class MediaExporter {
  /// 将 videoBook 的所有媒体文件打包成一个 ZIP 文件，并返回其字节数据。
  static Future<Uint8List> exportVideoBookMediaAsZip(BookshelfEntry entry) async {
    try {
      // 1. 加载并解析 video_book.json
      final jsonPath = p.join(entry.subCachePath, 'video_book.json');
      final file = File(jsonPath);
      if (!await file.exists()) {
        throw Exception('video_book.json not found!');
      }
      final jsonString = await file.readAsString();
      final jsonMap = jsonDecode(jsonString);
      final videoBook = VideoBook.fromJson(jsonMap);

      final archive = Archive();

      // 2. 遍历章节、场景、分镜来收集媒体文件
      for (final chapter in videoBook.script) {
        for (final scene in chapter.scenes) {
          for (final shot in scene.shots) {
            // 处理图片
            int imageIndex = 1;
            for (final imagePath in shot.firstFrameImagePaths) {
              await _addFileToArchive(
                archive,
                sourcePath: imagePath,
                chapter: chapter,
                scene: scene,
                shot: shot,
                type: 'image',
                index: imageIndex++,
              );
            }
            // 处理视频
            int videoIndex = 1;
            for (final videoPath in shot.videoPaths) {
              await _addFileToArchive(
                archive,
                sourcePath: videoPath,
                chapter: chapter,
                scene: scene,
                shot: shot,
                type: 'video',
                index: videoIndex++,
              );
            }
          }
        }
      }

      // 3. 将内存中的 archive 编码成 ZIP 字节流
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      LogService.instance.success('Successfully created media package for "${entry.title}".');
      return Uint8List.fromList(zipData);

    } catch (e, s) {
      LogService.instance.error('Failed to export video book media', e, s);
      throw Exception('导出媒体包失败: $e');
    }
  }

  /// 辅助方法：将单个文件添加到 Archive 中
  static Future<void> _addFileToArchive(
    Archive archive, {
    required String sourcePath,
    required ChapterScript chapter,
    required Scene scene,
    required Shot shot,
    required String type, // 'image' or 'video'
    required int index,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      LogService.instance.warn('Media file not found, skipping: $sourcePath');
      return;
    }

    // 创建目录结构: 第1章-章节标题/场景1-场景标题/
    final chapterDir = '第${chapter.chapterNumber}章-${_sanitize(chapter.originalChapterTitle)}';
    final sceneDir = '场景${scene.sceneNumber}-${_sanitize(scene.titleController.text)}';

    // 创建文件名: 分镜1_image_1.png
    final extension = p.extension(sourcePath);
    final newFileName = '分镜${shot.shotNumber}_${type}_$index$extension';
    
    // 组合成最终在压缩包内的路径
    final archivePath = p.join(chapterDir, sceneDir, newFileName);

    final bytes = await sourceFile.readAsBytes();
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
  }

  /// 清理文件名中的非法字符
  static String _sanitize(String filename) {
    return filename.replaceAll(RegExp(r'[\/:*?"<>|]'), '_').trim();
  }
}