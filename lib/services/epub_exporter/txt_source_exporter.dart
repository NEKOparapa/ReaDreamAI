// lib/services/epub_exporter/txt_source_exporter.dart

part of 'epub_exporter.dart';

/// 内部实现类：处理 TXT 源文件，从头构建 EPUB。
class _TxtSourceExporter {
  Future<void> export(Book book, String outputPath) async {
    final archive = Archive();

    // 1. 添加 mimetype (必须未压缩且在开头)
    final mimetypeContent = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile.noCompress(
      'mimetype',
      mimetypeContent.length,
      mimetypeContent,
    ));

    // 2. 添加 META-INF/container.xml
    final containerXml = _buildContainerXml();
    archive.addFile(ArchiveFile(
      'META-INF/container.xml',
      utf8.encode(containerXml).length,
      utf8.encode(containerXml),
    ));

    // 3. 收集所有媒体文件 (图片和视频)
    final mediaPaths = _MediaHelper.collectAllMediaPaths(book);

    // 4. 构建并添加 OEBPS/content.opf
    final opfContent = await _buildOpfContent(book, mediaPaths);
    archive.addFile(ArchiveFile(
      'OEBPS/content.opf',
      utf8.encode(opfContent).length,
      utf8.encode(opfContent),
    ));

    // 5. 构建并添加 OEBPS/toc.ncx
    final ncxContent = _buildNcxContent(book);
    archive.addFile(ArchiveFile(
      'OEBPS/toc.ncx',
      utf8.encode(ncxContent).length,
      utf8.encode(ncxContent),
    ));

    // 6. 构建并添加章节 HTML 文件
    int chapterIndex = 1;
    for (final chapter in book.chapters) {
      final htmlContent = _buildChapterHtml(chapter);
      archive.addFile(ArchiveFile(
        'OEBPS/chapter$chapterIndex.html',
        utf8.encode(htmlContent).length,
        utf8.encode(htmlContent),
      ));
      chapterIndex++;
    }

    // 7. 添加 CSS 样式表
    final cssContent = _buildCssContent();
    archive.addFile(ArchiveFile(
      'OEBPS/styles.css',
      utf8.encode(cssContent).length,
      utf8.encode(cssContent),
    ));

    // 8. 复制所有媒体文件到 OEBPS/ 目录
    await _MediaHelper.addMediaToArchive(archive, mediaPaths, 'OEBPS');

    // 9. 压缩并写入文件
    final epubData = ZipEncoder().encode(archive);
    if (epubData != null) {
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  String _buildContainerXml() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
  }

  Future<String> _buildOpfContent(Book book, Set<String> mediaPaths) async {
    final uuid = 'urn:uuid:${book.id}';
    final timestamp = DateTime.now().toIso8601String();

    String manifestItems = '';
    String spineItems = '';

    // 章节列表
    int chapterIndex = 1;
    for (final chapter in book.chapters) {
      manifestItems +=
          '<item id="chapter$chapterIndex" href="chapter$chapterIndex.html" media-type="application/xhtml+xml"/>\n';
      spineItems += '<itemref idref="chapter$chapterIndex"/>\n';
      chapterIndex++;
    }

    // 媒体文件 (图片和视频) 列表
    int mediaId = 1;
    for (final path in mediaPaths) {
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      String mediaType;
      String folder;
      if (extension == '.mp4') {
        mediaType = 'video/mp4';
        folder = 'videos';
      } else {
        mediaType = 'image/${extension.replaceAll('.', '')}';
        folder = 'images';
      }
      manifestItems +=
          '<item id="media_$mediaId" href="$folder/$fileName" media-type="$mediaType"/>\n';
      mediaId++;
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="uuid-id">$uuid</dc:identifier>
    <dc:title>${book.title}</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:creator>AiMoee Exporter</dc:creator>
    <meta property="dcterms:modified">$timestamp</meta>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="style" href="styles.css" media-type="text/css"/>
    $manifestItems
  </manifest>
  <spine toc="ncx">
    $spineItems
  </spine>
</package>''';
  }

  String _buildNcxContent(Book book) {
    String navPoints = '';
    int chapterIndex = 1;
    int playOrder = 1;
    for (final chapter in book.chapters) {
      navPoints += '''
        <navPoint id="chapter$chapterIndex" playOrder="$playOrder">
          <navLabel><text>${chapter.title}</text></navLabel>
          <content src="chapter$chapterIndex.html"/>
        </navPoint>
      ''';
      chapterIndex++;
      playOrder++;
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:${book.id}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>${book.title}</text>
  </docTitle>
  <navMap>
    $navPoints
  </navMap>
</ncx>''';
  }

  String _buildChapterHtml(ChapterStructure chapter) {
    String content = '';
    for (final line in chapter.lines) {
      final text = line.translatedText?.isNotEmpty == true ? line.translatedText! : line.text;
      final safeText = text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      content += '<p>$safeText</p>\n';

      if (line.illustrationPaths.isNotEmpty) {
        for (final imagePath in line.illustrationPaths) {
          content += _MediaHelper.generateImageHtml(p.basename(imagePath), relativePrefix: '');
        }
      }
      if (line.videoPaths.isNotEmpty) {
        for (final videoPath in line.videoPaths) {
          content += _MediaHelper.generateVideoHtml(p.basename(videoPath), relativePrefix: '');
        }
      }
    }
    return '''<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <title>${chapter.title}</title>
  <link rel="stylesheet" type="text/css" href="styles.css" />
</head>
<body>
  <h1>${chapter.title}</h1>
  $content
</body>
</html>''';
  }

  String _buildCssContent() {
    return '''
body { font-family: serif; line-height: 1.6; margin: 1em; padding: 0; }
h1 { font-size: 1.5em; text-align: center; margin-bottom: 1em; }
p { text-indent: 2em; margin: 0.5em 0; }
video { background-color: #000; }''';
  }
}