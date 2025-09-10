// lib/services/file_parser/file_parser.dart

import 'package:path/path.dart' as p;
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../cache_manager/cache_manager.dart';

// 导入新的子解析器
import 'txt_parser.dart';
import 'epub_parser.dart';

class FileParser {
  /// 主入口：解析、创建子缓存、返回书架条目
  /// 这个方法现在作为调度器，根据文件类型调用相应的解析器。
  static Future<BookshelfEntry?> parseAndCreateCache(String originalPath) async {
    try {
      final cacheManager = CacheManager();

      // 1. 创建缓存文件夹和复制源文件
      final (bookId, cachedPath, bookCacheDir) = await cacheManager.createBookCacheInfrastructure(originalPath);

      final bookTitle = p.basenameWithoutExtension(originalPath);
      final fileType = p.extension(originalPath).substring(1).toLowerCase();

      // 2. 根据文件类型调度到不同的解析器
      List<ChapterStructure> chapters;
      String? coverImagePath;

      if (fileType == 'txt') {
        chapters = await TxtParser.parse(cachedPath);
      } else if (fileType == 'epub') {
        final epubResult = await EpubParser.parse(cachedPath, bookCacheDir);
        chapters = epubResult.chapters;
        coverImagePath = epubResult.coverImagePath;
      } else {
        print('不支持的文件格式: $fileType');
        return null; // 不支持的格式
      }

      // 3. 构建完整的 Book 对象
      final newBook = Book(
        id: bookId,
        title: bookTitle,
        fileType: fileType,
        originalPath: originalPath,
        cachedPath: cachedPath,
        chapters: chapters,
        coverImagePath: coverImagePath,
      );

      // 4. 保存 Book 对象到它自己的子缓存文件
      final subCachePath = await cacheManager.saveBookDetail(newBook);

      // 5. 创建并返回轻量级的书架条目
      final newEntry = BookshelfEntry(
        id: bookId,
        title: bookTitle,
        originalPath: originalPath,
        fileType: fileType,
        subCachePath: subCachePath,
        coverImagePath: coverImagePath,
      );

      print('书籍 ${newBook.title} 解析并缓存成功。');
      return newEntry;
    } catch (e, s) {
      print('处理文件失败: $originalPath, 错误: $e');
      print('Stack trace: $s');
      return null;
    }
  }
}