// lib/services/epub_exporter/epub_source_exporter.dart

part of 'epub_exporter.dart';

/// 内部实现类：处理 EPUB 源文件，解包修改后重新打包。
class _EpubSourceExporter {
  Future<void> export(Book book, String outputPath) async {
    // 1. 读取并解压原始 EPUB
    final originalFile = File(book.originalPath);
    final archive = ZipDecoder().decodeBytes(await originalFile.readAsBytes());

    // 2. 找到 OPF 文件
    final opfPath = _findOpfPath(archive);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('找不到 OPF 文件: $opfPath');
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);

    // 3. 收集所有需要新增的媒体文件
    final newMediaPaths = _MediaHelper.collectAllMediaPaths(book);

    // 4. 遍历 Spine，修改 HTML 文件
    await _modifyEpubHtmlFiles(book, archive, opfDoc, opfPath);

    // 5. 更新 OPF Manifest，添加新媒体引用
    _updateOpfWithMedia(opfDoc, newMediaPaths);

    // 6. 将更新后的 OPF 写回 Archive
    final updatedOpfContent = opfDoc.toXmlString(pretty: true);
    archive.files.removeWhere((file) => file.name == opfPath);
    archive.addFile(ArchiveFile(opfPath, utf8.encode(updatedOpfContent).length, utf8.encode(updatedOpfContent)));

    // 7. 将新的媒体文件添加到 Archive
    final oebpsDir = p.dirname(opfPath);
    await _MediaHelper.addMediaToArchive(archive, newMediaPaths, oebpsDir);

    // 8. 重新打包
    final epubData = ZipEncoder().encode(archive);
    if (epubData != null) {
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  String _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('META-INF/container.xml not found');
    final content = utf8.decode(containerFile.content as List<int>);
    try {
      final doc = XmlDocument.parse(content);
      return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
    } catch (e) {
      throw Exception('解析 container.xml 失败: $e');
    }
  }

  Future<void> _modifyEpubHtmlFiles(Book book, Archive archive, XmlDocument opfDoc, String opfPath) async {
    final manifest = _parseManifest(opfDoc);
    final spine = _parseSpine(opfDoc);
    final oebpsDir = p.dirname(opfPath);

    for (final itemIdref in spine) {
      final sourceHref = manifest[itemIdref];
      if (sourceHref == null) continue;

      final chapterFilePath = p.join(oebpsDir, sourceHref).replaceAll('\\', '/');
      final chapterFile = archive.findFile(chapterFilePath);
      if (chapterFile == null) {
        print('警告: Spine 中引用的文件不存在: $chapterFilePath');
        continue;
      }

      final chapter = book.chapters.firstWhere(
        (ch) => ch.sourceFile.contains(p.basename(sourceHref)),
        orElse: () => ChapterStructure(title: "Unknown", sourceFile: "", lines: []),
      );
      if (chapter.lines.isEmpty) continue;

      final chapterHtml = utf8.decode(chapterFile.content as List<int>);
      final relativePrefix = _calculateRelativePrefix(sourceHref);
      final modifiedHtml = _modifyHtmlContent(chapterHtml, chapter, relativePrefix);

      archive.files.removeWhere((file) => file.name == chapterFilePath);
      archive.addFile(ArchiveFile(chapterFilePath, utf8.encode(modifiedHtml).length, utf8.encode(modifiedHtml)));
    }
  }

  String _calculateRelativePrefix(String href) {
    final segments = p.split(href);
    return segments.length > 1 ? '../' * (segments.length - 1) : '';
  }

  String _modifyHtmlContent(String html, ChapterStructure chapter, String relativePrefix) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return html;

    final textNodes = _findTextNodes(body);

    for (final line in chapter.lines) {
      final nodesToProcess = textNodes.where((node) => node.text.contains(line.originalContent)).toList();
      for (final node in nodesToProcess) {
        final parent = node.parent;
        if (parent == null) continue;

        List<html_dom.Node> mediaElements = [];
        if (line.videoPaths.isNotEmpty) {
          for (final videoPath in line.videoPaths) {
            final videoHtml = _MediaHelper.generateVideoHtml(p.basename(videoPath), relativePrefix: relativePrefix);
            mediaElements.add(html_dom.Element.html(videoHtml));
          }
        }
        if (line.illustrationPaths.isNotEmpty) {
          for (final imagePath in line.illustrationPaths) {
            final imageHtml = _MediaHelper.generateImageHtml(p.basename(imagePath), relativePrefix: relativePrefix);
            mediaElements.add(html_dom.Element.html(imageHtml));
          }
        }

        for (final mediaElement in mediaElements) {
          if (parent.parent != null && node == parent.nodes.first) {
            parent.parent!.insertBefore(mediaElement, parent);
          } else {
            parent.insertBefore(mediaElement, node);
          }
        }

        if (line.translatedText != null && line.translatedText!.isNotEmpty) {
          node.text = node.text.replaceFirst(line.originalContent, line.translatedText!);
        }
      }
    }
    return document.outerHtml;
  }

  List<html_dom.Text> _findTextNodes(html_dom.Element element) {
    final textNodes = <html_dom.Text>[];
    void traverse(html_dom.Node node) {
      if (node is html_dom.Text && node.text.trim().isNotEmpty) {
        textNodes.add(node);
      } else if (node is html_dom.Element && node.localName != 'script' && node.localName != 'style') {
        node.nodes.forEach(traverse);
      }
    }
    traverse(element);
    return textNodes;
  }

  Map<String, String> _parseManifest(XmlDocument opfDoc) {
    final manifest = <String, String>{};
    opfDoc.findAllElements('item').forEach((node) {
      final id = node.getAttribute('id');
      final href = node.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    });
    return manifest;
  }

  List<String> _parseSpine(XmlDocument opfDoc) {
    final spine = <String>[];
    opfDoc.findAllElements('itemref').forEach((node) {
      final idref = node.getAttribute('idref');
      if (idref != null) spine.add(idref);
    });
    return spine;
  }

  void _updateOpfWithMedia(XmlDocument opfDoc, Set<String> newMediaPaths) {
    final manifest = opfDoc.findAllElements('manifest').first;
    final existingHrefs = manifest.findAllElements('item').map((item) => item.getAttribute('href')).whereType<String>().toSet();

    final mediaToAdd = <String>{};
    for (final path in newMediaPaths) {
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      String folder = (extension == '.mp4') ? 'videos' : 'images';
      final relativePath = '$folder/$fileName';
      if (!existingHrefs.contains(relativePath)) mediaToAdd.add(path);
    }
    if (mediaToAdd.isEmpty) return;

    int nextId = manifest.findAllElements('item').length + 1;
    for (final path in mediaToAdd) {
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      String mediaType, folder, idPrefix;
      if (extension == '.mp4') {
        mediaType = 'video/mp4'; folder = 'videos'; idPrefix = 'video';
      } else {
        mediaType = 'image/${extension.replaceAll('.', '')}'; folder = 'images'; idPrefix = 'image';
      }
      final relativePath = '$folder/$fileName';
      String finalId = '${idPrefix}_$nextId';
      while (manifest.findAllElements('item').any((item) => item.getAttribute('id') == finalId)) {
         nextId++;
         finalId = '${idPrefix}_$nextId';
      }
      manifest.children.add(XmlElement(XmlName('item'), [
        XmlAttribute(XmlName('id'), finalId),
        XmlAttribute(XmlName('href'), relativePath),
        XmlAttribute(XmlName('media-type'), mediaType),
      ]));
      nextId++;
    }
  }
}