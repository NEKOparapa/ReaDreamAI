// lib/services/file_parser/file_parser.dart

import 'package:path/path.dart' as p;
import '../../models/book.dart';
import '../../models/bookshelf_entry.dart';
import '../cache_manager/cache_manager.dart';
import '../../base/log/log_service.dart'; 

// 导入子解析器
import 'txt_parser.dart';
import 'epub_parser.dart';

/// 文件解析器
class FileParser {
  static Future<BookshelfEntry?> parseAndCreateCache(String originalPath) async {
    try {
      final cacheManager = CacheManager();

      // 1. 创建书籍缓存所需的基础设施（如缓存目录），并复制源文件到缓存区。
      final (bookId, cachedPath, bookCacheDir) = await cacheManager.createBookCacheInfrastructure(originalPath);

      // 从路径中提取书名和文件类型
      final bookTitle = p.basenameWithoutExtension(originalPath);
      final fileType = p.extension(originalPath).substring(1).toLowerCase();

      // 2. 根据文件类型，调度到相应的子解析器进行解析。
      List<ChapterStructure> chapters;
      String? coverImagePath;

      if (fileType == 'txt') {
        // 调用 TXT 解析器
        chapters = await TxtParser.parse(cachedPath);
      } else if (fileType == 'epub') {
        // 调用 EPUB 解析器
        final epubResult = await EpubParser.parse(cachedPath, bookCacheDir);
        chapters = epubResult.chapters;
        coverImagePath = epubResult.coverImagePath;
      } else {
        // 记录不支持的文件格式
        LogService.instance.warn('尝试解析不支持的文件格式: $fileType, 文件路径: $originalPath');
        return null; // 返回 null 表示不支持或解析失败
      }

      // 3. 构建包含所有详细信息的完整 Book 对象。
      final newBook = Book(
        id: bookId,
        title: bookTitle,
        fileType: fileType,
        originalPath: originalPath,
        cachedPath: cachedPath,
        chapters: chapters,
        coverImagePath: coverImagePath,
      );

      // 4. 将完整的 Book 对象序列化并保存到它自己的缓存文件中，供后续快速读取。
      final subCachePath = await cacheManager.saveBookDetail(newBook);

      // 5. 创建并返回一个轻量级的书架条目（BookshelfEntry），用于在主界面快速加载和显示。
      final newEntry = BookshelfEntry(
        id: bookId,
        title: bookTitle,
        originalPath: originalPath,
        fileType: fileType,
        subCachePath: subCachePath,
        coverImagePath: coverImagePath,
      );
      
      // 记录成功日志
      LogService.instance.success('书籍 "$bookTitle" 解析并缓存成功。');
      return newEntry;
    } catch (e, s) {
      // 捕获并记录解析过程中发生的任何异常
      LogService.instance.error('处理文件失败: $originalPath', e, s);
      return null;
    }
  }
}