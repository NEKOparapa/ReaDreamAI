// lib/services/file_parser/epub_parser.dart

import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';
import '../../base/log/log_service.dart'
;
/// 解析 EPUB 文件的工具类。
/// 1. 将 EPUB 文件完全解压到书籍的缓存子目录中。
/// 2. 在解压后的目录中，按文件名暴力搜索封面图片。
/// 3. 找到并解析 container.xml，以定位 OPF 文件的路径。
/// 4. 在解压后的目录中，找到并解析 OPF 文件，获取 manifest 和 spine 信息。
/// 5. 根据 manifest 找到 NCX (目录) 文件。
/// 6. 根据 spine (书脊) 的顺序，遍历章节文件。
/// 7. 对每个章节文件，在解压后的目录中按文件名找到它，并解析其内容。
/// 8. 整合信息，构建 Book 对象。

class EpubParser {
  static Future<({List<ChapterStructure> chapters, String? coverImagePath})> parse(
      String cachedPath, Directory bookCacheDir) async {
    LogService.instance.info('--- 开始解析 EPUB: $cachedPath ---');

    // 1. 将 EPUB (本质是zip) 文件解压到缓存目录下的 "unzipped_epub" 子文件夹中
    final unzippedDir = Directory(p.join(bookCacheDir.path, 'unzipped_epub'));
    if (await unzippedDir.exists()) {
      await unzippedDir.delete(recursive: true); // 清理旧的解压文件
    }
    await unzippedDir.create(recursive: true);
    await _unzipEpub(cachedPath, unzippedDir);
    LogService.instance.info('EPUB 文件已成功解压到: ${unzippedDir.path}');

    // 2. 尝试通过常见的封面文件名在解压目录中快速查找封面图片。
    final coverImagePath = await _findCoverImageByFilename(unzippedDir);
    if (coverImagePath != null) {
      LogService.instance.info('通过文件名搜索找到封面: $coverImagePath');
    } else {
      LogService.instance.info('未能在解压目录中找到常见的封面文件名。');
    }

    // 3. 找到并解析 container.xml 文件，以定位 OPF (Open Packaging Format) 文件的路径。
    final containerFile = File(p.join(unzippedDir.path, 'META-INF', 'container.xml'));
    if (!await containerFile.exists()) {
      throw Exception('EPUB 验证错误: 未找到 META-INF/container.xml');
    }
    final opfRelativePath = await _findOpfPathFromContainerFile(containerFile);
    LogService.instance.info('从 container.xml 找到 OPF 相对路径: $opfRelativePath');

    // 在解压目录中找到 OPF 文件实体
    final opfFile = await _findFileInDirectory(unzippedDir, p.basename(opfRelativePath));
    if (opfFile == null) {
      LogService.instance.error('在解压目录中未找到 OPF 文件: ${p.basename(opfRelativePath)}');
      throw Exception('EPUB中未找到 .opf 文件');
    }
    LogService.instance.info('在文件系统中定位到 OPF 文件: ${opfFile.path}');
    
    // 4. 解析 OPF 文件的 XML 内容
    final opfContent = await opfFile.readAsString();
    final opfDoc = XmlDocument.parse(opfContent);

    // 5. 从 OPF 中解析清单（manifest）和书脊（spine），前者定义所有资源，后者定义阅读顺序。
    final manifest = _parseManifest(opfDoc);
    LogService.instance.info('解析清单完成，共 ${manifest.length} 个项目。');
    final spineHrefs = _parseSpine(opfDoc, manifest);
    LogService.instance.info('解析书脊完成，共 ${spineHrefs.length} 个项目按阅读顺序排列。');

    // 6. 查找并解析 NCX (目录) 文件以获取章节标题和顺序。
    final ncxPathEntry = manifest.entries.firstWhere(
      (e) => e.key.contains('ncx') || e.value.endsWith('.ncx'),
      orElse: () => const MapEntry('', ''),
    );

    final chapters = <ChapterStructure>[];
    int globalLineIdCounter = 0;

    // 7. 根据目录信息（NCX）和阅读顺序（Spine）来解析章节内容
    if (ncxPathEntry.value.isNotEmpty) {
      final ncxFileName = p.basename(ncxPathEntry.value);
      final ncxFile = await _findFileInDirectory(unzippedDir, ncxFileName);
      LogService.instance.info('尝试在解压目录中查找 NCX 文件: $ncxFileName');

      if (ncxFile != null) {
        // 如果找到 NCX 文件，优先使用它来构建章节结构
        LogService.instance.info('成功定位到 NCX 文件: ${ncxFile.path}');
        final navPoints = await _parseNcx(ncxFile);
        LogService.instance.info('解析 NCX 完成，共 ${navPoints.length} 个导航点 (章节/子章节)。');

        ChapterStructure? currentChapter; // 用于处理跨多个HTML文件的章节
        int navIndex = 0;

        for (final spineHref in spineHrefs) {
          final chapterFileName = p.basename(spineHref);
          final chapterFile = await _findFileInDirectory(unzippedDir, chapterFileName);
          
          if (chapterFile == null) {
            LogService.instance.warn('spine 中指定的文件在解压目录中未找到: $chapterFileName');
            continue;
          }
          LogService.instance.info('--> 正在处理 spine 文件: ${chapterFile.path}');

          final chapterHtml = await chapterFile.readAsString();
          XmlDocument? doc;
          try {
            doc = XmlDocument.parse(chapterHtml);
          } catch (e) {
            LogService.instance.error('解析 ${chapterFile.path} 的 XML 失败', e);
            continue;
          }

          final contentElements = _getContentElements(doc);
          if (contentElements.isEmpty) {
            LogService.instance.info('在 ${chapterFile.path} 中未找到内容元素，跳过。');
            continue;
          }

          // 匹配当前 HTML 文件中的 NCX 导航点
          final List<int> startIndices = [];
          final List<String> titles = [];
          while (navIndex < navPoints.length && p.basename(navPoints[navIndex].srcFile) == chapterFileName) {
            final anchor = navPoints[navIndex].anchor;
            int startIndex = 0;
            if (anchor != null) {
              final foundIndex = contentElements.indexWhere((el) => el.getAttribute('id') == anchor);
              startIndex = foundIndex >= 0 ? foundIndex : 0;
            }
            startIndices.add(startIndex);
            titles.add(navPoints[navIndex].title);
            navIndex++;
          }

          int elementIndex = 0;
          
          // 处理跨文件的章节（上一文件的末尾部分）
          if (currentChapter != null) {
            LogService.instance.info('  [延续] 章节 "${currentChapter.title}"，内容来自 ${chapterFile.path}');
            final int end = startIndices.isNotEmpty ? startIndices[0] : contentElements.length;
            for (; elementIndex < end; elementIndex++) {
              final line = _createLineFromElement(
                contentElements[elementIndex],
                globalLineIdCounter++,
                p.relative(chapterFile.path, from: unzippedDir.path),
              );
              if (line != null) currentChapter.lines.add(line);
            }
            if (startIndices.isEmpty) {
              continue; // 当前文件内容全部属于上一章节，继续处理下一个文件
            } else {
              chapters.add(currentChapter); // 上一章节结束
              LogService.instance.info('  [完成] 跨文件章节 "${currentChapter.title}"。');
              currentChapter = null;
            }
          }

          // 处理当前文件内定义的章节
          if (startIndices.isNotEmpty) {
            for (int j = 0; j < startIndices.length; j++) {
              final int start = startIndices[j];
              final int end = (j + 1 < startIndices.length) ? startIndices[j + 1] : contentElements.length;
              
              currentChapter = ChapterStructure(
                id: const Uuid().v4(),
                title: titles[j],
                sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
                lines: [],
              );
              LogService.instance.info('  [创建] 新章节 "${currentChapter.title}"，来自文件 ${chapterFile.path}');

              for (elementIndex = start; elementIndex < end; elementIndex++) {
                final line = _createLineFromElement(
                  contentElements[elementIndex],
                  globalLineIdCounter++,
                  p.relative(chapterFile.path, from: unzippedDir.path),
                );
                if (line != null) currentChapter.lines.add(line);
              }
            }
          } else {
            // 如果文件有内容但没有对应的 NCX 条目，则创建无标题章节
            if (currentChapter == null) {
              LogService.instance.info('文件 ${chapterFile.path} 有内容但无对应NCX条目。创建“无标题”章节。');
              final lines = <LineStructure>[];
              for (final el in contentElements) {
                final line = _createLineFromElement(el, globalLineIdCounter++, p.relative(chapterFile.path, from: unzippedDir.path));
                if (line != null) lines.add(line);
              }
              if (lines.isNotEmpty) {
                chapters.add(ChapterStructure(
                  id: const Uuid().v4(),
                  title: '无标题章节',
                  sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
                  lines: lines,
                ));
              }
            }
          }
        }
        
        // 添加最后一个可能跨文件的章节
        if (currentChapter != null && currentChapter.lines.isNotEmpty) {
          chapters.add(currentChapter);
          LogService.instance.info('添加最后一个处理的章节: "${currentChapter.title}"');
        }

      } else {
        // 如果找不到 NCX 文件，则回退到仅使用 spine 来生成章节
        LogService.instance.warn('NCX 文件已指定但在解压目录中未找到。回退到基于 spine 的章节生成。');
        chapters.addAll(await _fallbackToSpine(unzippedDir, spineHrefs, globalLineIdCounter));
      }
    } else {
      // 如果清单中就没有 NCX 文件，也回退到 spine
      LogService.instance.info('在清单中未找到 NCX 文件。回退到基于 spine 的章节生成。');
      chapters.addAll(await _fallbackToSpine(unzippedDir, spineHrefs, globalLineIdCounter));
    }

    LogService.instance.success('--- EPUB 解析完成。共找到 ${chapters.length} 个章节。 ---');
    return (chapters: chapters, coverImagePath: coverImagePath);
  }

  /// 辅助方法：将 EPUB (zip) 文件解压到指定目录。
  static Future<void> _unzipEpub(String epubPath, Directory destinationDir) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filePath = p.join(destinationDir.path, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }
  
  /// 辅助方法：在指定目录中递归查找文件（不关心路径，只匹配文件名）。
  static Future<File?> _findFileInDirectory(Directory dir, String fileName) async {
    final completer = Completer<File?>();
    late StreamSubscription<FileSystemEntity> subscription;

    subscription = dir.list(recursive: true, followLinks: false).listen(
      (FileSystemEntity entity) {
        if (entity is File && p.basename(entity.path) == fileName) {
          if (!completer.isCompleted) {
            completer.complete(entity);
            subscription.cancel(); // 找到后立即停止搜索
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(null); // 搜索完成但未找到
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
    );
    return completer.future;
  }

  /// 辅助方法：通过遍历常见文件名来查找封面图片。
  static Future<String?> _findCoverImageByFilename(Directory unzippedDir) async {
    const commonNames = [
      'cover.jpg', 'cover.jpeg', 'cover.png', 'cover.gif',
      'Cover.jpg', 'Cover.jpeg', 'Cover.png', 'Cover.gif',
      'cover-image.jpg', 'cover-image.jpeg', 'cover-image.png',
    ];

    for (final name in commonNames) {
      final foundFile = await _findFileInDirectory(unzippedDir, name);
      if (foundFile != null) {
        return foundFile.path;
      }
    }
    return null;
  }
  
  /// 辅助方法：从 `META-INF/container.xml` 文件中找到 `.opf` 文件的相对路径。
  static Future<String> _findOpfPathFromContainerFile(File containerFile) async {
    final content = await containerFile.readAsString();
    final doc = XmlDocument.parse(content);
    return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
  }

  /// 辅助方法：从 XML 元素创建 LineStructure 对象。
  static LineStructure? _createLineFromElement(XmlElement el, int id, String sourceInfo) {
    final cleanText = el.innerText.trim();
    if (cleanText.isEmpty) return null; // 忽略空行
    return LineStructure(
      id: id,
      text: cleanText,
      sourceInfo: sourceInfo, // 记录来源文件
      originalContent: el.toXmlString(pretty: false), // 保留原始HTML
    );
  }
  
  /// 辅助方法：从HTML文档中提取所有内容元素（如<p>, <h1>等）。
  static List<XmlElement> _getContentElements(XmlDocument doc) {
    final elements = <XmlElement>[];
    void visit(XmlNode node) {
      if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
        // 匹配<p>和<h1>到<h6>标签
        if (name == 'p' || RegExp(r'^h[1-6]$').hasMatch(name)) {
          elements.add(node);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }
    final body = doc.findElements('body').firstOrNull ?? doc.rootElement;
    visit(body);
    return elements;
  }

  /// 辅助方法：当NCX解析失败或不存在时，仅根据spine的顺序生成章节。
  static Future<List<ChapterStructure>> _fallbackToSpine(
      Directory unzippedDir, List<String> spineHrefs, int globalLineIdCounter) async {
    LogService.instance.info('--- 正在执行基于 spine 的回退章节生成 ---');
    final chapters = <ChapterStructure>[];
    for (final spineHref in spineHrefs) {
      final chapterFileName = p.basename(spineHref);
      final chapterFile = await _findFileInDirectory(unzippedDir, chapterFileName);
      if (chapterFile == null) {
        LogService.instance.warn('WARN (fallback): Spine 项目在解压目录中未找到: $chapterFileName');
        continue;
      }

      LogService.instance.info('  [Fallback] 正在处理: ${chapterFile.path}');
      final chapterHtml = await chapterFile.readAsString();
      final doc = XmlDocument.parse(chapterHtml);
      final contentElements = _getContentElements(doc);
      if (contentElements.isEmpty) continue;

      final lines = <LineStructure>[];
      String title = '无标题章节';
      bool titleFound = false;
      
      // 尝试从<h1>等标签中提取标题
      for (final el in contentElements) {
        final line = _createLineFromElement(el, globalLineIdCounter++, p.relative(chapterFile.path, from: unzippedDir.path));
        if (line != null) {
          lines.add(line);
          if (!titleFound && RegExp(r'^h[1-6]$', caseSensitive: false).hasMatch(el.name.local)) {
            title = line.text.length > 50 ? '${line.text.substring(0, 50)}...' : line.text;
            titleFound = true;
          }
        }
      }

      if (lines.isNotEmpty) {
        LogService.instance.info('  [Fallback] 创建章节: "$title"');
        chapters.add(ChapterStructure(
          id: const Uuid().v4(),
          title: title,
          sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
          lines: lines,
        ));
      }
    }
    return chapters;
  }

  /// 辅助方法：解析OPF文件中的spine部分，获取阅读顺序。
  static List<String> _parseSpine(XmlDocument opfDoc, Map<String, String> manifest) {
    final spineHrefs = <String>[];
    opfDoc.findAllElements('itemref').forEach((node) {
      final idref = node.getAttribute('idref');
      if (idref != null && manifest.containsKey(idref)) {
        spineHrefs.add(manifest[idref]!);
      } else {
        LogService.instance.warn('在清单中未找到 idref="$idref" 的 spine 项目。');
      }
    });
    return spineHrefs;
  }

  /// 辅助方法：解析OPF文件中的manifest部分，获取资源清单。
  static Map<String, String> _parseManifest(XmlDocument opfDoc) {
    final manifest = <String, String>{};
    opfDoc.findAllElements('item').forEach((node) {
      final id = node.getAttribute('id');
      final href = node.getAttribute('href');
      if (id != null && href != null) {
        final normalizedHref = href.replaceAll('\\', '/'); // 统一路径分隔符
        manifest[id] = Uri.decodeComponent(normalizedHref);
      }
    });
    return manifest;
  }

  /// 辅助方法：解析NCX文件，提取章节标题、源文件和锚点。
  static Future<List<({String title, String srcFile, String? anchor})>> _parseNcx(File ncxFile) async {
    final navPoints = <({String title, String srcFile, String? anchor})>[];
    final content = await ncxFile.readAsString();
    final doc = XmlDocument.parse(content);

    doc.findAllElements('navPoint').forEach((node) {
      try {
        final srcNode = node.findElements('content').firstOrNull;
        final labelNode = node.findElements('navLabel').firstOrNull?.findElements('text').firstOrNull;

        if (srcNode != null && labelNode != null) {
          final src = srcNode.getAttribute('src') ?? '';
          final title = labelNode.innerText.trim();

          if (src.isNotEmpty && title.isNotEmpty) {
            final parts = src.split('#'); // 分离文件名和锚点
            final normalizedSrc = Uri.decodeComponent(parts[0]).replaceAll('\\', '/');
            final anchor = parts.length > 1 ? parts[1] : null;
            navPoints.add((title: title, srcFile: normalizedSrc, anchor: anchor));
          }
        }
      } catch (e) {
        LogService.instance.error('无法解析 NCX 文件中的一个 <navPoint> 元素', e);
      }
    });
    return navPoints;
  }
}