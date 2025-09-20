// lib/services/file_parser/epub_parser.dart

import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

/// 解析 EPUB 文件的工具类。
/// 新的解析流程：
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
    print('[INFO] --- 开始解析 EPUB: $cachedPath ---');

    // 1. 解压 EPUB 文件到缓存目录下的 "unzipped_epub" 子文件夹
    final unzippedDir = Directory(p.join(bookCacheDir.path, 'unzipped_epub'));
    if (await unzippedDir.exists()) {
      await unzippedDir.delete(recursive: true);
    }
    await unzippedDir.create(recursive: true);
    await _unzipEpub(cachedPath, unzippedDir);
    print('[INFO] EPUB 文件已成功解压到: ${unzippedDir.path}');

    // 2. 在解压后的文件夹中按常见文件名遍历查找封面文件
    final coverImagePath = await _findCoverImageByFilename(unzippedDir);
    if (coverImagePath != null) {
      print('[INFO] 通过文件名搜索找到封面: $coverImagePath');
    } else {
      print('[INFO] 未能在解压目录中找到常见的封面文件名。');
    }

    // 3. 找到并解析 container.xml 来定位 OPF 文件
    final containerFile = File(p.join(unzippedDir.path, 'META-INF', 'container.xml'));
    if (!await containerFile.exists()) {
      throw Exception('EPUB 验证错误: 未找到 META-INF/container.xml');
    }
    final opfRelativePath = await _findOpfPathFromContainerFile(containerFile);
    print('[INFO] 从 container.xml 找到 OPF 相对路径: $opfRelativePath');

    // 在解压目录中找到 OPF 文件实体
    final opfFile = await _findFileInDirectory(unzippedDir, p.basename(opfRelativePath));
    if (opfFile == null) {
      print('[ERROR] 在解压目录中未找到 OPF 文件: ${p.basename(opfRelativePath)}');
      throw Exception('EPUB中未找到 .opf 文件');
    }
    print('[INFO] 在文件系统中定位到 OPF 文件: ${opfFile.path}');
    
    // 4. 解析 OPF 文件的内容 (XML)
    final opfContent = await opfFile.readAsString();
    final opfDoc = XmlDocument.parse(opfContent);

    // 5. 从 OPF 中解析清单（manifest）和书脊（spine）
    final manifest = _parseManifest(opfDoc);
    print('[INFO] 解析清单完成，共 ${manifest.length} 个项目。');
    final spineHrefs = _parseSpine(opfDoc, manifest);
    print('[INFO] 解析书脊完成，共 ${spineHrefs.length} 个项目按阅读顺序排列。');

    // 6. 查找并解析 NCX (Navigation Center eXtended) 文件以获取目录（TOC）。
    final ncxPathEntry = manifest.entries.firstWhere(
      (e) => e.key.contains('ncx') || e.value.endsWith('.ncx'),
      orElse: () => const MapEntry('', ''),
    );

    final chapters = <ChapterStructure>[];
    int globalLineIdCounter = 0;

    // 7. 根据目录信息（NCX）和阅读顺序（Spine）来解析章节
    if (ncxPathEntry.value.isNotEmpty) {
      final ncxFileName = p.basename(ncxPathEntry.value);
      final ncxFile = await _findFileInDirectory(unzippedDir, ncxFileName);
      print('[INFO] 尝试在解压目录中查找 NCX 文件: $ncxFileName');

      if (ncxFile != null) {
        print('[INFO] 成功定位到 NCX 文件: ${ncxFile.path}');
        final navPoints = await _parseNcx(ncxFile);
        print('[INFO] 解析 NCX 完成，共 ${navPoints.length} 个导航点 (章节/子章节)。');

        ChapterStructure? currentChapter;
        int navIndex = 0;

        for (final spineHref in spineHrefs) {
          final chapterFileName = p.basename(spineHref);
          // 在解压目录中按文件名查找章节文件
          final chapterFile = await _findFileInDirectory(unzippedDir, chapterFileName);
          
          if (chapterFile == null) {
            print('[WARN] spine 中指定的文件在解压目录中未找到: $chapterFileName');
            continue;
          }
          print('--> 正在处理 spine 文件: ${chapterFile.path}');


          final chapterHtml = await chapterFile.readAsString();
          XmlDocument? doc;
          try {
            doc = XmlDocument.parse(chapterHtml);
          } catch (e) {
            print('[ERROR] 解析 ${chapterFile.path} 的 XML 失败: $e');
            continue;
          }

          final contentElements = _getContentElements(doc);
          if (contentElements.isEmpty) {
            print('[INFO] 在 ${chapterFile.path} 中未找到内容元素，跳过。');
            continue;
          }

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

          if (currentChapter != null) {
            print('  [延续] 章节 "${currentChapter.title}"，内容来自 ${chapterFile.path}');
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
              continue;
            } else {
              chapters.add(currentChapter);
              print('  [完成] 跨文件章节 "${currentChapter.title}"。');
              currentChapter = null;
            }
          }

          if (startIndices.isNotEmpty) {
            for (int j = 0; j < startIndices.length; j++) {
              final int start = startIndices[j];
              final int end = (j + 1 < startIndices.length) ? startIndices[j + 1] : contentElements.length;
              
              currentChapter = ChapterStructure(
                title: titles[j],
                sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
                lines: [],
              );
              print('  [创建] 新章节 "${currentChapter.title}"，来自文件 ${chapterFile.path}');

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
            if (currentChapter == null) {
              print('[INFO] 文件 ${chapterFile.path} 有内容但无对应NCX条目。创建“无标题”章节。');
              final lines = <LineStructure>[];
              for (final el in contentElements) {
                final line = _createLineFromElement(el, globalLineIdCounter++, p.relative(chapterFile.path, from: unzippedDir.path));
                if (line != null) lines.add(line);
              }
              if (lines.isNotEmpty) {
                chapters.add(ChapterStructure(
                  title: '无标题章节',
                  sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
                  lines: lines,
                ));
              }
            }
          }
        }

        if (currentChapter != null && currentChapter.lines.isNotEmpty) {
          chapters.add(currentChapter);
          print('[INFO] 添加最后一个处理的章节: "${currentChapter.title}"');
        }
      } else {
        print('[WARN] NCX 文件已指定但在解压目录中未找到。回退到基于 spine 的章节生成。');
        chapters.addAll(await _fallbackToSpine(unzippedDir, spineHrefs, globalLineIdCounter));
      }
    } else {
      print('[INFO] 在清单中未找到 NCX 文件。回退到基于 spine 的章节生成。');
      chapters.addAll(await _fallbackToSpine(unzippedDir, spineHrefs, globalLineIdCounter));
    }

    print('--- EPUB 解析完成。共找到 ${chapters.length} 个章节。 ---');
    return (chapters: chapters, coverImagePath: coverImagePath);
  }

  /// 将 EPUB (zip) 文件解压到指定目录。
  static Future<void> _unzipEpub(String epubPath, Directory destinationDir) async {
    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filePath = p.join(destinationDir.path, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        // 确保父目录存在
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }
  
  /// 在指定目录中递归查找文件（忽略路径，只匹配文件名）。
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

  /// 通过遍历常见文件名来查找封面图片。
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
  
  /// 从 `META-INF/container.xml` 文件中找到 `.opf` 文件的相对路径。
  static Future<String> _findOpfPathFromContainerFile(File containerFile) async {
    final content = await containerFile.readAsString();
    final doc = XmlDocument.parse(content);
    return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
  }


  static LineStructure? _createLineFromElement(XmlElement el, int id, String sourceInfo) {
    final cleanText = el.innerText.trim();
    if (cleanText.isEmpty) return null;
    return LineStructure(
      id: id,
      text: cleanText,
      sourceInfo: sourceInfo,
      originalContent: el.toXmlString(pretty: false),
    );
  }

  static List<XmlElement> _getContentElements(XmlDocument doc) {
    final elements = <XmlElement>[];
    void visit(XmlNode node) {
      if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
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

  static Future<List<ChapterStructure>> _fallbackToSpine(
      Directory unzippedDir, List<String> spineHrefs, int globalLineIdCounter) async {
    print('--- 正在执行基于 spine 的回退章节生成 ---');
    final chapters = <ChapterStructure>[];
    for (final spineHref in spineHrefs) {
      final chapterFileName = p.basename(spineHref);
      final chapterFile = await _findFileInDirectory(unzippedDir, chapterFileName);
      if (chapterFile == null) {
        print('WARN (fallback): Spine 项目在解压目录中未找到: $chapterFileName');
        continue;
      }

      print('  [Fallback] 正在处理: ${chapterFile.path}');
      final chapterHtml = await chapterFile.readAsString();
      final doc = XmlDocument.parse(chapterHtml);
      final contentElements = _getContentElements(doc);
      if (contentElements.isEmpty) continue;

      final lines = <LineStructure>[];
      String title = 'Untitled';
      bool titleFound = false;

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
        print('  [Fallback] 创建章节: "$title"');
        chapters.add(ChapterStructure(
          title: title,
          sourceFile: p.relative(chapterFile.path, from: unzippedDir.path),
          lines: lines,
        ));
      }
    }
    return chapters;
  }

  static List<String> _parseSpine(XmlDocument opfDoc, Map<String, String> manifest) {
    final spineHrefs = <String>[];
    opfDoc.findAllElements('itemref').forEach((node) {
      final idref = node.getAttribute('idref');
      if (idref != null && manifest.containsKey(idref)) {
        spineHrefs.add(manifest[idref]!);
      } else {
        print('[WARN] 在清单中未找到 idref="$idref" 的 spine 项目。');
      }
    });
    return spineHrefs;
  }

  static Map<String, String> _parseManifest(XmlDocument opfDoc) {
    final manifest = <String, String>{};
    opfDoc.findAllElements('item').forEach((node) {
      final id = node.getAttribute('id');
      final href = node.getAttribute('href');
      if (id != null && href != null) {
        final normalizedHref = href.replaceAll('\\', '/');
        manifest[id] = Uri.decodeComponent(normalizedHref);
      }
    });
    return manifest;
  }

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
            final parts = src.split('#');
            final normalizedSrc = Uri.decodeComponent(parts[0]).replaceAll('\\', '/');
            final anchor = parts.length > 1 ? parts[1] : null;
            navPoints.add((title: title, srcFile: normalizedSrc, anchor: anchor));
          }
        }
      } catch (e) {
        print('[ERROR] 无法解析 NCX 文件中的一个 <navPoint> 元素: $e');
      }
    });
    return navPoints;
  }
}