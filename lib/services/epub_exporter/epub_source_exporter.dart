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
      
      // 注意：这里的匹配逻辑可能需要根据实际情况调整
      // 假设 sourceFile 是唯一的，或者至少是文件名匹配
      final chapter = book.chapters.firstWhere(
        (ch) => ch.sourceFile == chapterFilePath || p.basename(ch.sourceFile) == p.basename(sourceHref),
        orElse: () => ChapterStructure(title: "Unknown", sourceFile: "", lines: []),
      );

      // 如果找不到对应的章节数据，则跳过
      if (chapter.lines.isEmpty) continue;

      final chapterHtml = utf8.decode(chapterFile.content as List<int>);
      final relativePrefix = _calculateRelativePrefix(sourceHref);
      final modifiedHtml = _modifyHtmlContent(chapterHtml, chapter, relativePrefix);
      
      // 仅当 HTML 内容实际发生改变时才写回，以提高效率
      if (modifiedHtml != chapterHtml) {
        archive.files.removeWhere((file) => file.name == chapterFilePath);
        archive.addFile(ArchiveFile(chapterFilePath, utf8.encode(modifiedHtml).length, utf8.encode(modifiedHtml)));
      }
    }
  }

  String _calculateRelativePrefix(String href) {
    final segments = p.split(href);
    return segments.length > 1 ? '../' * (segments.length - 1) : '';
  }

  String _modifyHtmlContent(String html, ChapterStructure chapter, String relativePrefix) {
    // 1. 预先筛选出需要修改的行，如果为空则直接返回原始HTML，避免不必要的解析
    final linesToModify = chapter.lines.where((line) {
      final hasTranslation = line.translatedText != null && line.translatedText!.isNotEmpty;
      final hasIllustrations = line.illustrationPaths.isNotEmpty;
      final hasVideos = line.videoPaths.isNotEmpty;
      return hasTranslation || hasIllustrations || hasVideos;
    }).toList();

    if (linesToModify.isEmpty) {
      return html; // 没有需要修改的内容，直接返回
    }

    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return html;

    // 2. 创建一个从原始HTML内容到DOM元素的映射，用于快速查找
    // 使用 querySelectorAll 保证元素顺序与文档流一致
    final contentElements = body.querySelectorAll('p, h1, h2, h3, h4, h5, h6');
    final elementMap = <String, List<html_dom.Element>>{};
    for (final element in contentElements) {
      // 使用 outerHtml 作为 key，因为它最能代表原始的、未修改的元素
      final key = element.outerHtml.trim();
      elementMap.putIfAbsent(key, () => []).add(element);
    }
    
    // 3. 遍历需要修改的行，并在文档中找到对应的元素进行操作
    for (final line in linesToModify) {
      final originalHtmlKey = line.originalContent.trim();
      
      // 检查映射中是否存在该元素
      if (elementMap.containsKey(originalHtmlKey) && elementMap[originalHtmlKey]!.isNotEmpty) {
        // 取出第一个匹配的元素进行处理，并将其从列表中移除，以处理重复段落的情况
        final targetElement = elementMap[originalHtmlKey]!.removeAt(0);
        final parent = targetElement.parent;
        if (parent == null) continue;

        // 插入图片
        if (line.illustrationPaths.isNotEmpty) {
          for (final imagePath in line.illustrationPaths) {
            final imageHtml = _MediaHelper.generateImageHtml(p.basename(imagePath), relativePrefix: relativePrefix);
            final imageElement = html_dom.Element.html(imageHtml);
            // 在目标元素之前插入
            parent.insertBefore(imageElement, targetElement);
          }
        }
        
        // 插入视频
        if (line.videoPaths.isNotEmpty) {
          for (final videoPath in line.videoPaths) {
            final videoHtml = _MediaHelper.generateVideoHtml(p.basename(videoPath), relativePrefix: relativePrefix);
            final videoElement = html_dom.Element.html(videoHtml);
            // 在目标元素之前插入
            parent.insertBefore(videoElement, targetElement);
          }
        }

        // 插入翻译文本
        if (line.translatedText != null && line.translatedText!.isNotEmpty) {
          final translationHtml = '''<p>${line.translatedText}</p>''';
          final translationElement = html_dom.Element.html(translationHtml);
          // 在目标元素之前插入
          parent.insertBefore(translationElement, targetElement);
        }
      } else {
        // 如果找不到元素，可以打印一个警告
        print('警告: 无法在HTML文件中找到匹配的原始内容: ${line.originalContent}');
      }
    }
    
    // 4. 返回修改后的完整HTML字符串
    return document.outerHtml;
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