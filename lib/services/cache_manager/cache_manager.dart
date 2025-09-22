// lib/services/cache_manager/cache_manager.dart

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../models/book.dart';
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
}