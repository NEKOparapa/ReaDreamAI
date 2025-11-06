// lib/services/cache_manager/cache_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../models/book.dart';
import '../../models/storyboard_script_model.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';
import '../../base/log/log_service.dart';

/// 缓存管理器
class CacheManager {
  // --- 单例模式实现 ---
  CacheManager._internal();
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;

  // --- 常量与私有变量 ---
  // 定义缓存目录的名称
  static const String _cacheDirName = 'BookProjectsCache';
  // 定义书架索引文件的名称
  static const String _bookshelfFileName = 'bookshelf.json';
  // 缓存目录的对象，延迟初始化
  Directory? _cacheDirectory;

  /// 获取缓存根目录，如果不存在则创建
  Future<Directory> _getCacheDirectory() async {
    // 如果已经获取过，直接返回
    if (_cacheDirectory != null) return _cacheDirectory!;
    // 从配置服务获取应用的主目录
    final baseDir = ConfigService().getAppDirectoryPath();
    // 拼接缓存目录的完整路径
    final cachePath = p.join(baseDir, _cacheDirName);
    _cacheDirectory = Directory(cachePath);
    // 检查目录是否存在，不存在则同步创建（包括所有父目录）
    if (!_cacheDirectory!.existsSync()) {
      _cacheDirectory!.createSync(recursive: true);
    }
    return _cacheDirectory!;
  }

  /// 为视频书创建缓存，并深度复制所有关联的媒体文件
  Future<void> createVideoBookCache({
    required String title,
    required String originalBookId,
    required VideoBook videoBook, // 接收 VideoBook 对象
  }) async {
    // 1. 为新的视频书生成唯一ID，并创建项目目录结构
    final newBookId = const Uuid().v4();
    final cacheDir = await _getCacheDirectory();
    final projectDir = Directory(p.join(cacheDir.path, newBookId));
    projectDir.createSync(recursive: true);

    // 为媒体文件创建子目录，保持整洁
    final imagesDir = Directory(p.join(projectDir.path, 'images'));
    imagesDir.createSync();
    final videosDir = Directory(p.join(projectDir.path, 'videos'));
    videosDir.createSync();

    // 辅助函数，用于复制文件并返回新路径
    Future<String> copyMediaFile(String oldPath, Directory destDir) async {
      try {
        final sourceFile = File(oldPath);
        if (!await sourceFile.exists()) {
          LogService.instance
              .warn('[视频书缓存] 源文件不存在，无法复制: $oldPath');
          return oldPath; // 返回旧路径，避免程序崩溃
        }
        // 使用 UUID + 原始文件名创建唯一的新文件名，防止冲突
        final newFileName = '${const Uuid().v4()}-${p.basename(oldPath)}';
        final newPath = p.join(destDir.path, newFileName);
        await sourceFile.copy(newPath);
        return newPath; // 返回新文件的路径
      } catch (e) {
        LogService.instance.error('[视频书缓存] 复制文件失败: $oldPath', e);
        return oldPath; // 复制失败也返回旧路径
      }
    }

    // 2. 遍历 VideoBook 结构，复制媒体文件并更新路径
    for (final chapter in videoBook.script) {
      for (final scene in chapter.scenes) {
        for (final shot in scene.shots) {
          // 处理首帧图片
          final newImagePaths = <String>[];
          for (final oldImagePath in shot.firstFrameImagePaths) {
            final newImagePath = await copyMediaFile(oldImagePath, imagesDir);
            newImagePaths.add(newImagePath);
          }
          shot.firstFrameImagePaths = newImagePaths;

          // 处理视频
          final newVideoPaths = <String>[];
          for (final oldVideoPath in shot.videoPaths) {
            final newVideoPath = await copyMediaFile(oldVideoPath, videosDir);
            newVideoPaths.add(newVideoPath);
          }
          shot.videoPaths = newVideoPaths;
        }
      }
    }

    // 3. 将路径已更新的 VideoBook 对象序列化并保存
    final contentFile = File(p.join(projectDir.path, 'video_book.json'));
    await contentFile.writeAsString(jsonEncode(videoBook.toJson()));

    // 4. 加载现有书架，准备添加新条目
    final entries = await loadBookshelf();

    // 5. 尝试从原始书籍复制封面图片
    String? newCoverImagePath;
    try {
      final originalEntry = entries.firstWhere((e) => e.id == originalBookId);
      if (originalEntry.coverImagePath != null &&
          originalEntry.coverImagePath!.isNotEmpty) {
        final coverFile = File(originalEntry.coverImagePath!);
        if (await coverFile.exists()) {
          final newCoverPath = p.join(projectDir.path, 'cover${p.extension(coverFile.path)}');
          await coverFile.copy(newCoverPath);
          newCoverImagePath = newCoverPath;
        }
      }
    } catch (e) {
      LogService.instance.warn('创建视频书时复制封面失败: $e');
    }

    // 6. 创建新的视频书条目
    final newEntry = BookshelfEntry(
      id: newBookId,
      title: title,
      originalPath: 'workbench-generated', // 标记为工作台生成
      fileType: 'videoBook', // 关键类型字段
      subCachePath: projectDir.path,
      coverImagePath: newCoverImagePath, // 使用新封面路径
    );

    // 7. 添加到书架列表并保存
    entries.add(newEntry);
    await saveBookshelf(entries);
  }

  /// 为新导入的书籍创建缓存内容
  Future<(String id, String cachedContentPath, Directory projectDir)> createBookCacheInfrastructure(String originalPath) async {
    final cacheDir = await _getCacheDirectory();
    // 使用UUID v4生成一个唯一的书籍ID
    final bookId = const Uuid().v4();
    // 在缓存根目录下创建以书籍ID命名的项目目录
    final projectDir = Directory(p.join(cacheDir.path, bookId));
    projectDir.createSync();

    final originalFile = File(originalPath);
    // 获取原始文件的扩展名
    final fileExtension = p.extension(originalPath);
    // 在项目目录中构建内容文件的缓存路径
    final cachedContentPath = p.join(projectDir.path, 'content$fileExtension');

    // 将原始文件复制到缓存路径
    await originalFile.copy(cachedContentPath);

    // 返回创建好的信息
    return (bookId, cachedContentPath, projectDir);
  }

  /// 从缓存中加载书架条目列表 (轻量级索引)
  Future<List<BookshelfEntry>> loadBookshelf() async {
    try {
      final cacheDir = await _getCacheDirectory();
      // 定位书架索引文件
      final bookshelfFile = File(p.join(cacheDir.path, _bookshelfFileName));
      if (await bookshelfFile.exists()) {
        final jsonString = await bookshelfFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        // 将JSON列表映射为BookshelfEntry对象列表
        return jsonList.map((json) => BookshelfEntry.fromJson(json)).toList();
      }
    } catch (e, s) {
      LogService.instance.error('加载书架失败', e, s);
    }
    // 如果失败或文件不存在，返回空列表
    return [];
  }

  /// 保存书架条目列表 (轻量级索引)
  Future<void> saveBookshelf(List<BookshelfEntry> entries) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final bookshelfFile = File(p.join(cacheDir.path, _bookshelfFileName));
      // 将对象列表转换为JSON列表
      final jsonList = entries.map((entry) => entry.toJson()).toList();
      // 将JSON编码为字符串并写入文件
      await bookshelfFile.writeAsString(jsonEncode(jsonList));
    } catch (e, s) {
      LogService.instance.error('保存书架失败', e, s);
    }
  }

  /// 加载单个书籍的详细数据（从其项目子目录中的JSON文件加载）
  Future<Book?> loadBookDetail(String bookId) async {
    try {
      final cacheDir = await _getCacheDirectory();
      // 定位特定书籍的详情JSON文件
      final subCacheFile = File(p.join(cacheDir.path, bookId, '$bookId.json'));
      if (await subCacheFile.exists()) {
        final jsonString = await subCacheFile.readAsString();
        // 从JSON字符串解析为Book对象
        return Book.fromJson(jsonDecode(jsonString));
      }
    } catch (e, s) {
      LogService.instance.error('加载书籍详情 $bookId 失败', e, s);
    }
    // 如果失败或文件不存在，返回null
    return null;
  }

  /// 保存单个书籍的详细数据（到其项目子目录中的JSON文件）
  Future<String> saveBookDetail(Book book) async {
    final cacheDir = await _getCacheDirectory();
    final subCacheFile = File(p.join(cacheDir.path, book.id, '${book.id}.json'));
    // 将Book对象编码为JSON字符串并写入文件
    await subCacheFile.writeAsString(jsonEncode(book.toJson()));
    return subCacheFile.path;
  }

  /// 从缓存中移除一本书（通过删除整个项目文件夹实现）
  Future<void> removeBookCacheFolder(String bookId) async {
    final cacheDir = await _getCacheDirectory();
    final projectDir = Directory(p.join(cacheDir.path, bookId));
    if (await projectDir.exists()) {
      // 递归删除整个目录及其所有内容
      await projectDir.delete(recursive: true);
      LogService.instance.info('项目缓存文件夹已删除: $bookId');
    }
  }

  /// 获取或创建书籍缓存下的特定子目录 (例如用于存放插图)
  Future<Directory> getOrCreateBookSubDir(String bookId, String subDirName) async {
    final cacheDir = await _getCacheDirectory();
    // 定位书籍的项目目录
    final bookDir = Directory(p.join(cacheDir.path, bookId));
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }
    // 在项目目录下定位子目录
    final subDir = Directory(p.join(bookDir.path, subDirName));
    if (!await subDir.exists()) {
      // 如果子目录不存在，则创建
      await subDir.create();
    }
    return subDir;
  }
  
  /// 更新书籍指定范围内的文本内容
  /// 此方法会替换指定章节中，从 startLineId 到 endLineId 之间的所有行
  /// 然后用 newContent 生成新的行来代替。
  /// 重新遍历整本书，为每一行分配一个新的、连续的ID。
  Future<Book?> updateTextInRange({
    required String bookId,
    required String chapterId,
    required int startLineId,
    required int endLineId,
    required String newContent,
  }) async {
    final book = await loadBookDetail(bookId);
    if (book == null) return null;

    try {
      final newChapters = <ChapterStructure>[];
      int globalLineIdCounter = 0;

      for (final chapter in book.chapters) {
        final List<LineStructure> newLinesForChapter;

        if (chapter.id != chapterId) {
          // A) 如果不是被修改的章节，只需为其所有行重新分配ID
          newLinesForChapter = chapter.lines.map((line) {
            return LineStructure(
              id: globalLineIdCounter++,
              text: line.text,
              sourceInfo: line.sourceInfo,
              originalContent: line.originalContent,
              illustrationPaths: line.illustrationPaths,
              videoPaths: line.videoPaths,
              sceneDescription: line.sceneDescription,
              translatedText: line.translatedText,
            );
          }).toList();
        } else {
          // B) 如果是目标章节，执行替换和重新ID分配
          newLinesForChapter = [];
          final startIdx = chapter.lines.indexWhere((l) => l.id == startLineId);
          final endIdx = chapter.lines.indexWhere((l) => l.id == endLineId);
          if (startIdx == -1 || endIdx == -1) {
             throw Exception("在章节 ${chapter.title} 中未找到指定的起始或结束行ID。");
          }

          // 1. 添加划选区域之前的所有行（并重新分配ID）
          for (int i = 0; i < startIdx; i++) {
            final line = chapter.lines[i];
            newLinesForChapter.add(LineStructure(
              id: globalLineIdCounter++, text: line.text, sourceInfo: line.sourceInfo, originalContent: line.originalContent,
              illustrationPaths: line.illustrationPaths, videoPaths: line.videoPaths, sceneDescription: line.sceneDescription, translatedText: line.translatedText,
            ));
          }

          // 2. 将 newContent 分割成新行并添加（分配新ID）
          if (newContent.isNotEmpty) {
            final contentLines = newContent.split('\n');
            for (final textLine in contentLines) {
              if (textLine.trim().isNotEmpty) {
                newLinesForChapter.add(
                  LineStructure(
                    id: globalLineIdCounter++,
                    text: textLine,
                    originalContent: textLine, // text和originalContent内容一样
                    sourceInfo: 'edited',
                    // 其他字段置空
                    illustrationPaths: [],
                    videoPaths: [],
                    sceneDescription: null,
                    translatedText: null,
                  ),
                );
              }
            }
          }

          // 3. 添加划选区域之后的所有行（并重新分配ID）
          for (int i = endIdx + 1; i < chapter.lines.length; i++) {
            final line = chapter.lines[i];
             newLinesForChapter.add(LineStructure(
              id: globalLineIdCounter++, text: line.text, sourceInfo: line.sourceInfo, originalContent: line.originalContent,
              illustrationPaths: line.illustrationPaths, videoPaths: line.videoPaths, sceneDescription: line.sceneDescription, translatedText: line.translatedText,
            ));
          }
        }
        
        // 用更新后的行列表创建新的章节对象
        newChapters.add(ChapterStructure(
          id: chapter.id, title: chapter.title, sourceFile: chapter.sourceFile,
          chapterSummary: chapter.chapterSummary, lines: newLinesForChapter,
        ));
      }

      // 用更新后的章节列表创建新的书籍对象
      final updatedBook = Book(
        id: book.id, title: book.title, fileType: book.fileType, originalPath: book.originalPath,
        cachedPath: book.cachedPath, coverImagePath: book.coverImagePath, backgroundSetting: book.backgroundSetting,
        writingStyle: book.writingStyle, characters: book.characters, chapters: newChapters,
      );

      // 保存更新后的书籍到缓存并返回
      await saveBookDetail(updatedBook);
      return updatedBook;

    } catch (e, s) {
      LogService.instance.error('更新书籍 $bookId 文本失败', e, s);
      return null;
    }
  }

  /// 更新指定章节的标题和全部内容
  /// 此方法会替换目标章节的标题和所有行，同时为了保持ID连续性，会重新为整本书的行分配ID。
  Future<Book?> updateChapterContent({
    required String bookId,
    required String chapterId,
    required String newTitle,
    required String newContent,
  }) async {
    final book = await loadBookDetail(bookId);
    if (book == null) return null;

    try {
      final newChapters = <ChapterStructure>[];
      int globalLineIdCounter = 0;

      for (final oldChapter in book.chapters) {
        final List<LineStructure> newLinesForChapter;
        final String updatedTitle;

        if (oldChapter.id == chapterId) {
          // 是目标章节：使用新标题，并根据新内容生成全新的行列表
          updatedTitle = newTitle;
          newLinesForChapter = [];
          final contentLines = newContent.split('\n');
          for (final textLine in contentLines) {
            // 过滤掉纯空白行
            if (textLine.trim().isNotEmpty) {
              newLinesForChapter.add(
                LineStructure(
                  id: globalLineIdCounter++,
                  text: textLine,
                  originalContent: textLine,
                  sourceInfo: 'rewritten', // 标记为重写
                  // 其他字段使用默认空值
                  illustrationPaths: [],
                  videoPaths: [],
                  sceneDescription: null,
                  translatedText: null,
                ),
              );
            }
          }
        } else {
          // 不是目标章节：沿用旧标题，并为旧行重新分配ID
          updatedTitle = oldChapter.title;
          newLinesForChapter = oldChapter.lines.map((line) {
            // 复制旧行，但赋予新的连续ID
            return LineStructure(
              id: globalLineIdCounter++,
              text: line.text,
              sourceInfo: line.sourceInfo,
              originalContent: line.originalContent,
              illustrationPaths: line.illustrationPaths,
              videoPaths: line.videoPaths,
              sceneDescription: line.sceneDescription,
              translatedText: line.translatedText,
            );
          }).toList();
        }
        
        // 使用更新后的信息创建新的章节对象
        newChapters.add(ChapterStructure(
          id: oldChapter.id,
          title: updatedTitle,
          sourceFile: oldChapter.sourceFile,
          chapterSummary: oldChapter.chapterSummary,
          timeSpan: oldChapter.timeSpan,
          settingUpdate: oldChapter.settingUpdate,
          lines: newLinesForChapter,
        ));
      }

      // 用更新后的章节列表创建新的书籍对象
      final updatedBook = Book(
        id: book.id, title: book.title, fileType: book.fileType, originalPath: book.originalPath,
        cachedPath: book.cachedPath, coverImagePath: book.coverImagePath, backgroundSetting: book.backgroundSetting,
        writingStyle: book.writingStyle, characters: book.characters, chapters: newChapters,
      );

      // 保存更新后的书籍到缓存并返回
      await saveBookDetail(updatedBook);
      return updatedBook;

    } catch (e, s) {
      LogService.instance.error('更新章节 $chapterId in book $bookId 失败', e, s);
      return null;
    }
  }
}