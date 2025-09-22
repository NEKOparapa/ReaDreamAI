// lib/services/epub_exporter/epub_source_exporter.dart

part of 'epub_exporter.dart';

/// 内部实现类：处理源文件为 EPUB 的情况。
/// 主要逻辑是解包现有的 EPUB，修改其内容（HTML、OPF），添加新媒体文件，然后重新打包。
class _EpubSourceExporter {
  /// 执行导出操作
  Future<void> export(Book book, String outputPath) async {
    // 步骤 1: 读取并解压原始 EPUB 文件到内存中的 Archive 对象。
    final originalFile = File(book.cachedPath);
    final archive = ZipDecoder().decodeBytes(await originalFile.readAsBytes());

    // 步骤 2: 解析 META-INF/container.xml 找到 OPF 文件的路径，并读取其内容。
    final opfPath = _findOpfPath(archive);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('找不到 OPF 文件: $opfPath');
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);

    // 步骤 3: 收集所有需要新增的媒体文件（图片、视频）的本地路径。
    final newMediaPaths = _MediaHelper.collectAllMediaPaths(book);
    LogService.instance.info('需要添加的媒体文件数量: ${newMediaPaths.length}');

    // 步骤 4: 构建一个映射，Key 是需要修改的 HTML 文件名，Value 是该文件中所有待修改行的列表。
    final filesToModify = _buildFilesToModifyMap(book);
    LogService.instance.info('需要修改的 HTML 文件数量: ${filesToModify.length}');
    filesToModify.forEach((fileName, lines) {
      LogService.instance.info('  文件 "$fileName" 中有 ${lines.length} 行需要修改');
    });

    // 步骤 5: 创建一个新的 Archive 对象，用于存放修改后的文件。
    final newArchive = Archive();
    final oebpsDir = p.dirname(opfPath); // 通常是 "OEBPS" 或 "OPS"

    // 步骤 6: 遍历原始 Archive 中的所有文件，进行复制或修改。
    for (final file in archive.files) {
      if (file.isFile) {
        if (file.name == opfPath) {
          // OPF 文件内容已更新，稍后统一添加，此处跳过。
          continue;
        }
        
        final archiveEntryBasename = p.basename(file.name);
        
        // 检查当前文件是否在待修改列表中。
        if (filesToModify.containsKey(archiveEntryBasename)) {
          // 如果是，则读取、修改内容，然后将修改后的内容添加到新 Archive 中。
          final linesToModify = filesToModify[archiveEntryBasename]!;
          final originalHtml = utf8.decode(file.content as List<int>);
          final fullArchivePath = file.name.replaceAll('\\', '/'); // 统一路径分隔符
          final modifiedHtml = _modifyHtmlContentWithLines(originalHtml, linesToModify, oebpsDir, fullArchivePath);
          
          if (modifiedHtml != originalHtml) {
            LogService.instance.info('已修改文件: ${file.name}');
            newArchive.addFile(ArchiveFile(file.name, utf8.encode(modifiedHtml).length, utf8.encode(modifiedHtml)));
          } else {
            // 如果内容没有实际变化，则保持原样（不压缩以提高效率）。
            newArchive.addFile(ArchiveFile.noCompress(file.name, file.size, file.content));
          }
        } else {
          // 如果文件不需要修改，则直接复制到新 Archive 中（不压缩）。
          newArchive.addFile(ArchiveFile.noCompress(file.name, file.size, file.content));
        }
      }
    }

    // 步骤 7: 更新 OPF 文件中的 manifest 节点，为新媒体文件添加引用。
    _updateOpfWithMedia(opfDoc, newMediaPaths);

    // 步骤 8: 将更新后的 OPF XML 内容写入新 Archive。
    final updatedOpfContent = opfDoc.toXmlString(pretty: true);
    newArchive.addFile(ArchiveFile(opfPath, utf8.encode(updatedOpfContent).length, utf8.encode(updatedOpfContent)));

    // 步骤 9: 将新的媒体文件（图片、视频）的二进制数据添加到新 Archive 中。
    await _MediaHelper.addMediaToArchive(newArchive, newMediaPaths, oebpsDir);

    // 步骤 10: 使用 ZipEncoder 将新 Archive 压缩成最终的 EPUB 文件数据。
    final epubData = ZipEncoder().encode(newArchive);
    if (epubData != null) {
      // 将压缩后的数据写入用户指定的输出路径。
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  /// 构建文件到需要修改的行的映射，Key 为文件名 (例如 "chapter1.html")。
  Map<String, List<LineStructure>> _buildFilesToModifyMap(Book book) {
    final filesToModify = <String, List<LineStructure>>{};
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        // 检查行是否有翻译、插图或视频，只要有任意一项就需要修改。
        final hasModifications = (line.translatedText != null && line.translatedText!.isNotEmpty) ||
            line.illustrationPaths.isNotEmpty ||
            line.videoPaths.isNotEmpty;
        
        if (hasModifications) {
          // 从 sourceInfo (原始 HTML 文件路径) 中提取文件名。
          final fileName = p.basename(line.sourceInfo);
          // 将此行添加到对应文件名的列表中。
          filesToModify.putIfAbsent(fileName, () => []).add(line);
        }
      }
    }
    return filesToModify;
  }

  /// 在给定的 HTML 内容中，根据 `linesToModify` 列表插入翻译、图片和视频。
  String _modifyHtmlContentWithLines(String html, List<LineStructure> linesToModify, String oebpsDir, String currentFilePath) {
    if (linesToModify.isEmpty) return html;

    LogService.instance.info('正在处理文件: $currentFilePath，需要修改 ${linesToModify.length} 行');

    // 计算当前 HTML 文件相对于媒体文件夹（如 OEBPS/images）的路径前缀，例如 "../"。
    final relativePrefix = _calculateRelativePrefixForFile(currentFilePath, oebpsDir);

    String modifiedHtml = html;
    int modifiedCount = 0;

    for (final line in linesToModify) {
      // 使用 `originalContent` 进行精确匹配，以找到在 HTML 中的插入点。
      final originalContent = line.originalContent.trim();
      
      if (originalContent.isEmpty) {
        LogService.instance.warn('Line ${line.id} 缺少 originalContent，无法定位修改点');
        continue;
      }
      
      final index = modifiedHtml.indexOf(originalContent);
      if (index == -1) {
        // 如果找不到匹配项，记录警告并跳过。
        LogService.instance.warn('无法在 HTML 中找到原始内容:\n  Line ID: ${line.id}\n  Original Content: $originalContent');
        continue;
      }
      
      modifiedCount++;
      
      // 构建要插入的新内容（图片、视频、翻译文本）。
      final insertions = StringBuffer();
      
      // 插入图片
      for (final imagePath in line.illustrationPaths) {
        insertions.write(_MediaHelper.generateImageHtml(
          p.basename(imagePath), 
          relativePrefix: relativePrefix
        ));
      }
      
      // 插入视频
      for (final videoPath in line.videoPaths) {
        insertions.write(_MediaHelper.generateVideoHtml(
          p.basename(videoPath), 
          relativePrefix: relativePrefix
        ));
      }
      
      // 插入翻译文本
      if (line.translatedText != null && line.translatedText!.isNotEmpty) {
        insertions.write('<p>${line.translatedText}</p>\n');
      }
      
      // 在原始内容之前插入新内容。
      if (insertions.isNotEmpty) {
        modifiedHtml = modifiedHtml.replaceFirst(
          originalContent,
          insertions.toString() + originalContent,
        );
      }
    }

    LogService.instance.info('文件 "$currentFilePath" 成功修改了 $modifiedCount/${linesToModify.length} 处');
    return modifiedHtml;
  }

  /// 根据文件在 Archive 中的完整路径，计算其相对于 OEBPS 根目录的路径前缀。
  /// 例如，"OEBPS/Text/chapter1.html" 的前缀是 "../"，用于正确引用 "OEBPS/images/" 下的图片。
  String _calculateRelativePrefixForFile(String archivePath, String oebpsDir) {
    // 移除 OEBPS 前缀，得到相对于 OEBPS 的路径
    final relativePath = archivePath.startsWith(oebpsDir) 
        ? archivePath.substring(oebpsDir.length).replaceAll('\\', '/')
        : archivePath.replaceAll('\\', '/');
    
    // 移除开头的斜杠
    final cleanPath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    
    // 计算路径深度，确定需要多少个 "../"
    final segments = cleanPath.split('/');
    return segments.length > 1 ? '../' * (segments.length - 1) : '';
  }

  /// 从 META-INF/container.xml 中查找并返回 OPF 文件的路径。
  String _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('未找到 META-INF/container.xml');
    final content = utf8.decode(containerFile.content as List<int>);
    try {
      final doc = XmlDocument.parse(content);
      return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
    } catch (e) {
      throw Exception('解析 container.xml 失败： $e');
    }
  }

  /// 更新 OPF 文件的 manifest，为新的媒体文件添加 item 条目。
  void _updateOpfWithMedia(XmlDocument opfDoc, Set<String> newMediaPaths) {
    final manifest = opfDoc.findAllElements('manifest').first;
    // 获取已有的所有文件引用 href，避免重复添加。
    final existingHrefs = manifest.findAllElements('item')
        .map((item) => item.getAttribute('href'))
        .whereType<String>()
        .toSet();

    // 筛选出尚未在 manifest 中声明的新媒体文件。
    final mediaToAdd = <String>{};
    for (final path in newMediaPaths) {
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      String folder = (extension == '.mp4') ? 'videos' : 'images';
      final relativePath = '$folder/$fileName';
      if (!existingHrefs.contains(relativePath)) mediaToAdd.add(path);
    }

    if (mediaToAdd.isEmpty) return; // 如果没有新文件需要添加，则直接返回。

    LogService.instance.info('正在向 OPF manifest 添加 ${mediaToAdd.length} 个新媒体条目...');
    int nextId = manifest.findAllElements('item').length + 1;

    for (final path in mediaToAdd) {
      final fileName = p.basename(path);
      final extension = p.extension(path).toLowerCase();
      String mediaType, folder, idPrefix;
      
      // 根据文件扩展名确定 media-type、存放目录和 ID 前缀。
      if (extension == '.mp4') {
        mediaType = 'video/mp4';
        folder = 'videos';
        idPrefix = 'video';
      } else {
        mediaType = 'image/${extension.replaceAll('.', '')}';
        folder = 'images';
        idPrefix = 'image';
      }
      
      final relativePath = '$folder/$fileName';
      String finalId = '${idPrefix}_$nextId';
      
      // 确保生成的 ID 是唯一的。
      while (manifest.findAllElements('item').any((item) => item.getAttribute('id') == finalId)) {
        nextId++;
        finalId = '${idPrefix}_$nextId';
      }
      
      // 创建并添加新的 <item> XML 元素。
      manifest.children.add(XmlElement(XmlName('item'), [
        XmlAttribute(XmlName('id'), finalId),
        XmlAttribute(XmlName('href'), relativePath),
        XmlAttribute(XmlName('media-type'), mediaType),
      ]));
      nextId++;
    }
  }
}