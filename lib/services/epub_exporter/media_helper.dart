// lib/services/epub_exporter/media_helper.dart

part of 'epub_exporter.dart';

/// 内部辅助类：封装处理媒体文件（图片、视频）的通用逻辑。
class _MediaHelper {
  /// 遍历整本书的数据结构，收集所有唯一的媒体文件本地路径。
  /// 使用 Set 可以自动去重。
  static Set<String> collectAllMediaPaths(Book book) {
    final mediaPaths = <String>{};
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        mediaPaths.addAll(line.illustrationPaths);
        mediaPaths.addAll(line.videoPaths);
      }
    }
    return mediaPaths;
  }

  /// 将指定路径的媒体文件读取并添加到内存中的 Archive 对象里。
  /// [archive] 目标 Archive。
  /// [mediaPaths] 要添加的媒体文件的本地路径集合。
  /// [destinationBase] 在 Archive 中的基础目标路径，通常是 "OEBPS"。
  static Future<void> addMediaToArchive(
    Archive archive,
    Set<String> mediaPaths,
    String destinationBase,
  ) async {
    for (final mediaPath in mediaPaths) {
      final mediaFile = File(mediaPath);
      if (await mediaFile.exists()) {
        // 根据文件扩展名确定其在 EPUB 内部的存放子目录（images 或 videos）。
        final fileName = p.basename(mediaPath);
        final extension = p.extension(mediaPath).toLowerCase();
        String folder = (extension == '.mp4') ? 'videos' : 'images';
        // 构建文件在 Archive 中的完整路径，并统一使用 '/' 作为路径分隔符。
        final archivePath = p.join(destinationBase, folder, fileName).replaceAll('\\', '/');

        // 读取文件内容并添加到 Archive 中。
        final mediaData = await mediaFile.readAsBytes();
        archive.addFile(ArchiveFile(archivePath, mediaData.length, mediaData));
      } else {
        // 如果文件不存在，记录一条警告日志。
        LogService.instance.warn('媒体文件不存在，已跳过: $mediaPath');
      }
    }
  }

  /// 根据文件名和相对路径前缀，生成用于插入 HTML 的图片标签。
  /// [relativePrefix] 用于处理不同层级目录下的 HTML 对图片路径的引用，例如 "../"。
  static String generateImageHtml(String fileName, {String relativePrefix = ''}) {
    final src = '${relativePrefix}images/$fileName';
    // 使用 div 包装以实现居中和边距效果。
    return '''
<div style="text-align: center; margin: 1em 0;">
  <img src="$src" alt="Illustration" style="max-width: 100%; height: auto;" />
</div>
''';
  }

  /// 根据文件名和相对路径前缀，生成用于插入 HTML 的视频标签。
  static String generateVideoHtml(String fileName, {String relativePrefix = ''}) {
    final src = '${relativePrefix}videos/$fileName';
    // 使用 div 包装，并为 video 标签添加 controls 属性。
    return '''
<div style="text-align: center; margin: 1em 0;">
  <video controls="controls" style="max-width: 100%; height: auto;">
    <source src="$src" type="video/mp4" />
    您的阅读器不支持 video 标签。
  </video>
</div>
''';
  }
}