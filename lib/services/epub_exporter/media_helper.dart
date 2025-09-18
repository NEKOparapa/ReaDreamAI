// lib/services/epub_exporter/media_helper.dart

part of 'epub_exporter.dart';

/// 内部辅助类：处理媒体文件（图片、视频）的通用逻辑。
class _MediaHelper {
  /// 收集书中所有唯一的媒体文件路径 (图片和视频)
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

  /// 将媒体文件复制到 Archive 中
  /// [destinationBase] 是 OEBPS 目录在 Archive 中的路径
  static Future<void> addMediaToArchive(
    Archive archive,
    Set<String> mediaPaths,
    String destinationBase,
  ) async {
    for (final mediaPath in mediaPaths) {
      final mediaFile = File(mediaPath);
      if (await mediaFile.exists()) {
        final fileName = p.basename(mediaPath);
        final extension = p.extension(mediaPath).toLowerCase();
        String folder = (extension == '.mp4') ? 'videos' : 'images';
        final archivePath = p.join(destinationBase, folder, fileName).replaceAll('\\', '/');

        final mediaData = await mediaFile.readAsBytes();
        archive.addFile(ArchiveFile(archivePath, mediaData.length, mediaData));
      } else {
        print('警告: 媒体文件不存在: $mediaPath');
      }
    }
  }

  /// 生成图片的 HTML (包含居中 div)
  static String generateImageHtml(String fileName, {String relativePrefix = ''}) {
    final src = '${relativePrefix}images/$fileName';
    return '''
<div style="text-align: center; margin: 1em 0;">
  <img src="$src" alt="Illustration" style="max-width: 100%; height: auto;" />
</div>
''';
  }

  /// 生成视频的 HTML (包含居中 div 和 controls)
  static String generateVideoHtml(String fileName, {String relativePrefix = ''}) {
    final src = '${relativePrefix}videos/$fileName';
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