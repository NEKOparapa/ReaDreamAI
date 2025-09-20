// lib/services/epub_exporter/epub_source_exporter.dart

part of 'epub_exporter.dart';

/// 处理 EPUB 源文件，解包修改后重新打包。
class _EpubSourceExporter {
  Future<void> export(Book book, String outputPath) async {
    // 1. 读取并解压原始 EPUB
    final originalFile = File(book.cachedPath);
    final archive = ZipDecoder().decodeBytes(await originalFile.readAsBytes());

    // 2. 找到 OPF 文件
    final opfPath = _findOpfPath(archive);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('找不到 OPF 文件: $opfPath');
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);

    // 3. 收集所有需要新增的媒体文件
    final newMediaPaths = _MediaHelper.collectAllMediaPaths(book);
    print('需要添加的媒体文件数量: ${newMediaPaths.length}');

    // 4. 构建需要修改的文件映射
    final oebpsDir = p.dirname(opfPath);
    final filesToModify = _buildFilesToModifyMap(book, oebpsDir);
    
    print('需要修改的文件数量: ${filesToModify.length}');
    filesToModify.forEach((path, lines) {
      print('  $path: ${lines.length} 行需要修改');
    });

    // 5. 创建一个新的 Archive 来存储修改后的文件
    final newArchive = Archive();

    // 6. 复制所有原始文件到新 Archive，同时处理需要修改的文件
    for (final file in archive.files) {
      if (file.isFile) {
        if (file.name == opfPath) {
          // OPF 文件稍后处理
          continue;
        }
        
        // 检查是否是需要修改的 HTML 文件
        final normalizedFileName = file.name.replaceAll('\\', '/');
        if (filesToModify.containsKey(normalizedFileName)) {
          // 修改文件
          final linesToModify = filesToModify[normalizedFileName]!;
          final originalHtml = utf8.decode(file.content as List<int>);
          final modifiedHtml = _modifyHtmlContentWithLines(originalHtml, linesToModify, oebpsDir, normalizedFileName);
          
          if (modifiedHtml != originalHtml) {
            print('已修改: ${file.name}');
            newArchive.addFile(ArchiveFile(file.name, utf8.encode(modifiedHtml).length, utf8.encode(modifiedHtml)));
          } else {
            newArchive.addFile(ArchiveFile.noCompress(file.name, file.size, file.content));
          }
        } else {
          // 保持原文件不变
          newArchive.addFile(ArchiveFile.noCompress(file.name, file.size, file.content));
        }
      }
    }

    // 7. 更新 OPF Manifest，添加新媒体引用
    _updateOpfWithMedia(opfDoc, newMediaPaths);

    // 8. 将更新后的 OPF 写入新 Archive
    final updatedOpfContent = opfDoc.toXmlString(pretty: true);
    newArchive.addFile(ArchiveFile(opfPath, utf8.encode(updatedOpfContent).length, utf8.encode(updatedOpfContent)));

    // 9. 将新的媒体文件添加到 Archive
    await _MediaHelper.addMediaToArchive(newArchive, newMediaPaths, oebpsDir);

    // 10. 重新打包
    final epubData = ZipEncoder().encode(newArchive);
    if (epubData != null) {
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  /// 构建文件路径到需要修改的行的映射
  Map<String, List<LineStructure>> _buildFilesToModifyMap(Book book, String oebpsDir) {
    final filesToModify = <String, List<LineStructure>>{};
    
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        // 检查是否需要修改
        final hasModifications = (line.translatedText != null && line.translatedText!.isNotEmpty) ||
            line.illustrationPaths.isNotEmpty ||
            line.videoPaths.isNotEmpty;
        
        if (hasModifications) {
          // 规范化 sourceInfo 路径
          final normalizedSourceInfo = line.sourceInfo.replaceAll('\\', '/');
          
          // 计算在 archive 中的实际路径
          final archivePath = p.posix.normalize(p.posix.join(oebpsDir, normalizedSourceInfo));
          
          // 添加到映射中
          filesToModify.putIfAbsent(archivePath, () => []).add(line);
        }
      }
    }
    
    return filesToModify;
  }

  /// 修改 HTML 内容，使用特定的行列表
  String _modifyHtmlContentWithLines(String html, List<LineStructure> linesToModify, String oebpsDir, String currentFilePath) {
    if (linesToModify.isEmpty) {
      return html;
    }

    print('处理文件: $currentFilePath，需要修改 ${linesToModify.length} 行');

    // 计算相对路径前缀
    final relativePrefix = _calculateRelativePrefixForFile(currentFilePath, oebpsDir);

    String modifiedHtml = html;
    int modifiedCount = 0;

    for (final line in linesToModify) {
      // 使用 originalContent 进行精确匹配
      final originalContent = line.originalContent.trim();
      
      if (originalContent.isEmpty) {
        print('警告: Line ${line.id} 缺少 originalContent');
        continue;
      }
      
      // 在 HTML 中查找原始内容的位置
      final index = modifiedHtml.indexOf(originalContent);
      
      if (index == -1) {
        print('警告: 无法在 HTML 中找到原始内容:');
        print('  Line ID: ${line.id}');
        print('  Original Content: $originalContent');
        continue;
      }
      
      modifiedCount++;
      
      // 构建要插入的新内容
      final insertions = StringBuffer();
      
      // 插入图片
      if (line.illustrationPaths.isNotEmpty) {
        for (final imagePath in line.illustrationPaths) {
          insertions.write(_MediaHelper.generateImageHtml(
            p.basename(imagePath), 
            relativePrefix: relativePrefix
          ));
          insertions.write('\n');
        }
      }
      
      // 插入视频
      if (line.videoPaths.isNotEmpty) {
        for (final videoPath in line.videoPaths) {
          insertions.write(_MediaHelper.generateVideoHtml(
            p.basename(videoPath), 
            relativePrefix: relativePrefix
          ));
          insertions.write('\n');
        }
      }
      
      // 插入翻译文本
      if (line.translatedText != null && line.translatedText!.isNotEmpty) {
        insertions.write('<p>${line.translatedText}</p>\n');
      }
      
      // 在原始内容之前插入新内容
      if (insertions.isNotEmpty) {
        modifiedHtml = modifiedHtml.replaceFirst(
          originalContent,
          insertions.toString() + originalContent,
        );
      }
    }

    print('成功修改了 $modifiedCount/${linesToModify.length} 行');

    return modifiedHtml;
  }

  /// 根据文件在 archive 中的路径计算相对路径前缀
  String _calculateRelativePrefixForFile(String archivePath, String oebpsDir) {
    // 移除 OEBPS 前缀，得到相对于 OEBPS 的路径
    final relativePath = archivePath.startsWith(oebpsDir) 
        ? archivePath.substring(oebpsDir.length).replaceAll('\\', '/')
        : archivePath.replaceAll('\\', '/');
    
    // 移除开头的斜杠
    final cleanPath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    
    // 计算需要多少个 ../ 才能回到 OEBPS 目录
    final segments = cleanPath.split('/');
    return segments.length > 1 ? '../' * (segments.length - 1) : '';
  }

  String _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('META-INF/container.xml not found');
    final content = utf8.decode(containerFile.content as List<int>);
    try {
      final doc = XmlDocument.parse(content);
      return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
    } catch (e) {
      throw Exception('解析 container.xml 失败： $e');
    }
  }

  void _updateOpfWithMedia(XmlDocument opfDoc, Set<String> newMediaPaths) {
    final manifest = opfDoc.findAllElements('manifest').first;
    final existingHrefs = manifest.findAllElements('item')
        .map((item) => item.getAttribute('href'))
        .whereType<String>()
        .toSet();

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
