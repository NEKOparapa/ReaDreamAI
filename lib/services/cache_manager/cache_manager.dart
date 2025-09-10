// lib/services/cache_manager/cache_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../../base/config_service.dart';

class CacheManager {
  CacheManager._internal();
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;

  static const String _cacheDirName = 'BookProjectsCache';
  static const String _bookshelfFileName = 'bookshelf.json';
  Directory? _cacheDirectory;

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    final baseDir = ConfigService().getAppDirectoryPath();
    final cachePath = p.join(baseDir, _cacheDirName);
    _cacheDirectory = Directory(cachePath);
    if (!_cacheDirectory!.existsSync()) {
      _cacheDirectory!.createSync(recursive: true);
    }
    return _cacheDirectory!;
  }

  /// 创建书籍的缓存结构，返回ID、内容路径和项目目录对象
  Future<(String id, String cachedContentPath, Directory projectDir)> createBookCacheInfrastructure(String originalPath) async {
    final cacheDir = await _getCacheDirectory();
    final bookId = const Uuid().v4();
    final projectDir = Directory(p.join(cacheDir.path, bookId));
    projectDir.createSync();

    final originalFile = File(originalPath);
    final fileExtension = p.extension(originalPath);
    final cachedContentPath = p.join(projectDir.path, 'content$fileExtension');

    await originalFile.copy(cachedContentPath);

    return (bookId, cachedContentPath, projectDir);
  }

  /// 从缓存中加载书架条目列表 (轻量级)
  Future<List<BookshelfEntry>> loadBookshelf() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final bookshelfFile = File(p.join(cacheDir.path, _bookshelfFileName));
      if (await bookshelfFile.exists()) {
        final jsonString = await bookshelfFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        return jsonList.map((json) => BookshelfEntry.fromJson(json)).toList();
      }
    } catch (e) {
      print('加载书架失败: $e');
    }
    return [];
  }

  /// 保存书架条目列表 (轻量级)
  Future<void> saveBookshelf(List<BookshelfEntry> entries) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final bookshelfFile = File(p.join(cacheDir.path, _bookshelfFileName));
      final jsonList = entries.map((entry) => entry.toJson()).toList();
      await bookshelfFile.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('保存书架失败: $e');
    }
  }

  /// 加载单个书籍的详细数据（从子缓存文件）
  Future<Book?> loadBookDetail(String bookId) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final subCacheFile = File(p.join(cacheDir.path, bookId, '$bookId.json'));
      if (await subCacheFile.exists()) {
        final jsonString = await subCacheFile.readAsString();
        return Book.fromJson(jsonDecode(jsonString));
      }
    } catch (e) {
      print('加载书籍详情 $bookId 失败: $e');
    }
    return null;
  }

  /// 保存单个书籍的详细数据（到子缓存文件）
  Future<String> saveBookDetail(Book book) async {
    final cacheDir = await _getCacheDirectory();
    final subCacheFile = File(p.join(cacheDir.path, book.id, '${book.id}.json'));
    await subCacheFile.writeAsString(jsonEncode(book.toJson()));
    return subCacheFile.path;
  }

  /// 从缓存中移除一本书（删除整个文件夹）
  Future<void> removeBookCacheFolder(String bookId) async {
    final cacheDir = await _getCacheDirectory();
    final projectDir = Directory(p.join(cacheDir.path, bookId));
    if (await projectDir.exists()) {
      await projectDir.delete(recursive: true);
      print('项目缓存文件夹已删除: $bookId');
    }
  }

  /// 获取或创建书籍缓存下的特定子目录 (例如用于存放插图)
  Future<Directory> getOrCreateBookSubDir(String bookId, String subDirName) async {
    final cacheDir = await _getCacheDirectory();
    final bookDir = Directory(p.join(cacheDir.path, bookId));
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }
    final subDir = Directory(p.join(bookDir.path, subDirName));
    if (!await subDir.exists()) {
      await subDir.create();
    }
    return subDir;
  }
}