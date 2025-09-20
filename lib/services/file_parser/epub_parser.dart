// lib/services/file_parser/epub_parser.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

/// 解析 EPUB 文件的工具类。
class EpubParser {
  static Future<({List<ChapterStructure> chapters, String? coverImagePath})> parse(
      String cachedPath, Directory bookCacheDir) async {
    print('[INFO] --- 开始解析 EPUB: $cachedPath ---');

    // 1. 在内存中解压 EPUB 归档文件
    final bytes = await File(cachedPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 2. 从 container.xml 中找到 OPF (Open Packaging Format) 文件的路径
    final opfPath = _findOpfPath(archive);
    print('[INFO] 找到 OPF 文件路径: $opfPath');
    // OPF 文件的目录是 EPUB 内部所有相对路径的根。
    final opfDir = p.dirname(opfPath);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      print('[ERROR] 在路径 $opfPath 未找到 .opf 文件');
      throw Exception('EPUB中未找到 .opf 文件');
    }

    // 3. 解析 OPF 文件的内容 (XML)
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);

    // 4. 从 OPF 中解析清单（manifest）
    final manifest = _parseManifest(opfDoc);
    print('[INFO] 解析清单完成，共 ${manifest.length} 个项目。');

    // 5. 提取并保存封面图片
    String? coverImagePath;
    final coverHref = _findCoverImageHref(opfDoc, manifest);
    if (coverHref != null) {
      print('[INFO] 找到封面图片 href: $coverHref');
      // 构建相对于归档根目录的完整路径。
      final coverFileRelPath = p.join(opfDir, coverHref).replaceAll('\\', '/');
      final coverArchiveFile = archive.findFile(coverFileRelPath);
      if (coverArchiveFile != null) {
        // 将封面图片保存到书籍的缓存目录中。
        final coverImageFile = File(p.join(bookCacheDir.path, 'cover${p.extension(coverHref)}'));
        await coverImageFile.writeAsBytes(coverArchiveFile.content as Uint8List);
        coverImagePath = coverImageFile.path;
        print('[INFO] 成功提取并保存封面到: $coverImagePath');
      } else {
        print('WARN: 在清单中找到封面图片 href，但在归档中未找到文件: $coverFileRelPath');
      }
    } else {
      print('[INFO] 在 EPUB 元数据中未找到封面图片。');
    }

    // 6. 解析书脊（spine）以获取按阅读顺序排列的内容文件。
    // 书脊决定了书籍的线性阅读顺序。
    final spineHrefs = _parseSpine(opfDoc, manifest);
    print('[INFO] 解析书脊完成，共 ${spineHrefs.length} 个项目按阅读顺序排列。');

    // 7. 查找并解析 NCX (Navigation Center eXtended) 文件以获取目录（TOC）。
    final ncxPathEntry = manifest.entries.firstWhere(
      (e) => e.key.contains('ncx') || e.value.endsWith('.ncx'), // 识别 NCX 文件的常见方式
      orElse: () => const MapEntry('', ''),
    );

    final chapters = <ChapterStructure>[];
    int globalLineIdCounter = 0; // 为所有章节中的每一行分配一个唯一的 ID。

    // 8. 如果存在 NCX 文件，则使用它来处理章节。这能提供正确的章节标题。
    if (ncxPathEntry.value.isNotEmpty) {
      final ncxPath = p.join(opfDir, ncxPathEntry.value).replaceAll('\\', '/');
      final tocFile = archive.findFile(ncxPath);
      print('[INFO] 找到 NCX (TOC) 文件于: $ncxPath');

      if (tocFile != null) {
        final navPoints = _parseNcx(tocFile);
        print('[INFO] 解析 NCX 完成，共 ${navPoints.length} 个导航点 (章节/子章节)。');

        // 这个复杂的循环旨在协调阅读顺序（spine）和目录（navPoints）。
        // 一个章节可能跨越多个文件，或者一个文件可能包含多个章节。
        ChapterStructure? currentChapter; // 当前正在构建的章节。
        int navIndex = 0; // 指向当前正在处理的 navPoint 的指针。

        // 按照指定的阅读顺序（spine）遍历每个内容文件。
        for (final spineHref in spineHrefs) {
          final chapterFilePath = p.join(opfDir, spineHref).replaceAll('\\', '/');
          print('--> 正在处理 spine 文件: $chapterFilePath');

          final chapterFile = archive.findFile(chapterFilePath);
          if (chapterFile == null) {
            print('[WARN] spine 中指定的文件在归档中未找到: $chapterFilePath');
            continue;
          }

          final chapterHtml = utf8.decode(chapterFile.content as List<int>);
          XmlDocument? doc;
          try {
            // 解析文件的 HTML/XHTML 内容。
            doc = XmlDocument.parse(chapterHtml);
          } catch (e) {
            print('[ERROR] 解析 $chapterFilePath 的 XML 失败: $e');
            continue; // 如果文件格式错误，则跳过。
          }

          // 按文档顺序提取所有承载内容的元素（<p>, <h1>, 等）。
          final contentElements = _getContentElements(doc);
          if (contentElements.isEmpty) {
            print('[INFO] 在 $chapterFilePath 中未找到内容元素，跳过。');
            continue;
          }

          // 找出所有位于此 spine 文件中的章节起点（navPoints）。
          final List<int> startIndices = [];
          final List<String> titles = [];
          while (navIndex < navPoints.length && navPoints[navIndex].srcFile == spineHref) {
            final anchor = navPoints[navIndex].anchor;
            int startIndex = 0; // 默认从文件开头开始。
            if (anchor != null) {
              // 如果指定了锚点（如 "chapter1.xhtml#section2"），则找到具有该 ID 的元素。
              final foundIndex = contentElements.indexWhere((el) => el.getAttribute('id') == anchor);
              startIndex = foundIndex >= 0 ? foundIndex : 0;
            }
            startIndices.add(startIndex);
            titles.add(navPoints[navIndex].title);
            navIndex++;
          }

          int elementIndex = 0; // 指向此文件中当前正在处理的内容元素的指针。

          // 情况 1: 一个来自 *上一个* 文件的章节延续到 *这个* 文件中。
          if (currentChapter != null) {
            print('  [延续] 章节 "${currentChapter.title}"，内容来自 $chapterFilePath');
            // 确定此章节内容在当前文件中的结束位置。
            // 结束于下一个章节的开始处，或文件末尾。
            final int end = startIndices.isNotEmpty ? startIndices[0] : contentElements.length;
            for (; elementIndex < end; elementIndex++) {
              final line = _createLineFromElement(
                contentElements[elementIndex],
                globalLineIdCounter++,
                chapterFilePath,
              );
              if (line != null) {
                currentChapter.lines.add(line);
              }
            }
            // 如果此文件中没有新的章节开始，我们将继续处理下一个文件。
            if (startIndices.isEmpty) {
              continue; // 此文件的内容已完全附加到上一章节。
            } else {
              // 此文件中有新章节开始，因此前一个章节已构建完成。
              chapters.add(currentChapter);
              print('  [完成] 跨文件章节 "${currentChapter.title}"。');
              currentChapter = null;
            }
          }

          // 情况 2: 处理所有在此文件中开始的新章节。
          if (startIndices.isNotEmpty) {
            for (int j = 0; j < startIndices.length; j++) {
              final int start = startIndices[j];
              // 结束索引是下一个章节的开始，或者是文件的末尾。
              final int end = (j + 1 < startIndices.length) ? startIndices[j + 1] : contentElements.length;

              // 创建一个新章节。
              currentChapter = ChapterStructure(
                title: titles[j],
                sourceFile: chapterFilePath,
                lines: [],
              );
              print('  [创建] 新章节 "${currentChapter.title}"，来自文件 $chapterFilePath');

              // 添加属于此章节片段的所有内容元素。
              // 注意: 如果我们延续了上一章节，elementIndex 已经被推进了。
              for (elementIndex = start; elementIndex < end; elementIndex++) {
                final line = _createLineFromElement(
                  contentElements[elementIndex],
                  globalLineIdCounter++,
                  chapterFilePath,
                );
                if (line != null) {
                  currentChapter.lines.add(line);
                }
              }
            }
          } else {
            // 情况 3: 此文件有内容，但没有对应的 NCX 条目（例如，版权页）。
            // 如果没有 `currentChapter` 可以附加内容，我们将其视为一个“无标题”章节。
            if (currentChapter == null) {
              print('[INFO] 文件 $chapterFilePath 有内容但无对应NCX条目。创建“无标题”章节。');
              final lines = <LineStructure>[];
              for (final el in contentElements) {
                final line = _createLineFromElement(el, globalLineIdCounter++, chapterFilePath);
                if (line != null) lines.add(line);
              }
              if (lines.isNotEmpty) {
                chapters.add(ChapterStructure(
                  title: '无标题章节',
                  sourceFile: chapterFilePath,
                  lines: lines,
                ));
              }
            }
          }
        } // spine 循环结束。

        // 循环结束后，最后一个章节可能仍在 `currentChapter` 中。将其添加。
        if (currentChapter != null && currentChapter.lines.isNotEmpty) {
          chapters.add(currentChapter);
          print('[INFO] 添加最后一个处理的章节: "${currentChapter.title}"');
        }
      } else {
        // 回退情况 A: NCX 路径在清单中，但文件在归档中缺失。
        print('[WARN] NCX 文件已指定但在归档中未找到。回退到基于 spine 的章节生成。');
        chapters.addAll(await _fallbackToSpine(archive, opfDir, spineHrefs, globalLineIdCounter));
      }
    } else {
      // 回退情况 B: 清单中未列出 NCX 文件。
      print('[INFO] 在清单中未找到 NCX 文件。回退到基于 spine 的章节生成。');
      chapters.addAll(await _fallbackToSpine(archive, opfDir, spineHrefs, globalLineIdCounter));
    }

    print('--- EPUB 解析完成。共找到 ${chapters.length} 个章节。 ---');
    return (chapters: chapters, coverImagePath: coverImagePath);
  }

  /// 从一个 XML 元素创建一个 `LineStructure` 对象。
  ///
  /// 提取并清理文本内容。如果元素在修剪后不包含有意义的文本，则返回 `null`。
  static LineStructure? _createLineFromElement(XmlElement el, int id, String sourceInfo) {
    // 修剪空白和换行符以获取核心文本。
    final cleanText = el.innerText.trim();
    // 忽略空元素 (例如, <p></p> or <p>  </p>)。
    if (cleanText.isEmpty) return null;

    return LineStructure(
      id: id,
      text: cleanText,
      sourceInfo: sourceInfo, // 用于调试和未来功能。
      originalContent: el.toXmlString(pretty: false), // 保留原始 HTML 以便渲染。
    );
  }

  /// 从 XML 文档中提取所有承载内容的元素（`<p>` 和 `<h1-h6>`）。
  ///
  /// 此函数对 XML 树执行深度优先遍历，以确保元素按其自然的文档顺序返回。
  /// 如果存在 `<body>` 标签，则从 `<body>` 开始搜索，否则从根元素开始。
  static List<XmlElement> _getContentElements(XmlDocument doc) {
    final elements = <XmlElement>[];
    void visit(XmlNode node) {
      if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
        // 检查段落或任意级别的标题标签。
        if (name == 'p' || RegExp(r'^h[1-6]$').hasMatch(name)) {
          elements.add(node);
        }
      }
      // 递归访问子节点以保持顺序。
      for (final child in node.children) {
        visit(child);
      }
    }
    // 优先在 <body> 标签内搜索以保证正确性。
    final body = doc.findElements('body').firstOrNull;
    if (body != null) {
      visit(body);
    } else {
      // 对可能没有 <body> 标签的文档进行回退。
      visit(doc.rootElement);
    }
    return elements;
  }

  /// 当没有 NCX (TOC) 文件可用时使用的回退章节生成方法。
  ///
  /// 它将 `spine`（阅读顺序）中的每个文件视为一个单独的章节。
  /// 章节标题通过启发式方法确定：查找文件中的第一个标题标签（`<h1-h6>`）的文本。
  /// 如果未找到标题，则标题为“Untitled”。
  static Future<List<ChapterStructure>> _fallbackToSpine(
      Archive archive, String opfDir, List<String> spineHrefs, int globalLineIdCounter) async {
    print('--- 正在执行基于 spine 的回退章节生成 ---');
    final chapters = <ChapterStructure>[];
    for (final spineHref in spineHrefs) {
      final chapterFilePath = p.join(opfDir, spineHref).replaceAll('\\', '/');
      final chapterFile = archive.findFile(chapterFilePath);
      if (chapterFile == null) {
        print('WARN (fallback): Spine 项目在归档中未找到: $chapterFilePath');
        continue;
      }

      print('  [Fallback] 正在处理: $chapterFilePath');
      final chapterHtml = utf8.decode(chapterFile.content as List<int>);
      final doc = XmlDocument.parse(chapterHtml);
      final contentElements = _getContentElements(doc);
      if (contentElements.isEmpty) continue;

      final lines = <LineStructure>[];
      String title = 'Untitled'; // 默认标题。
      bool titleFound = false;

      for (final el in contentElements) {
        final line = _createLineFromElement(el, globalLineIdCounter++, chapterFilePath);
        if (line != null) {
          lines.add(line);
          // 使用找到的第一个标题作为章节标题。
          if (!titleFound && RegExp(r'^h[1-6]$', caseSensitive: false).hasMatch(el.name.local)) {
            // 截断长标题以保持整洁。
            title = line.text.length > 50 ? '${line.text.substring(0, 50)}...' : line.text;
            titleFound = true;
          }
        }
      }

      // 仅当章节包含实际内容时才添加。
      if (lines.isNotEmpty) {
        print('  [Fallback] 创建章节: "$title"，来自文件 $chapterFilePath');
        chapters.add(ChapterStructure(
          title: title,
          sourceFile: chapterFilePath,
          lines: lines,
        ));
      }
    }
    return chapters;
  }

  /// 解析 OPF 文档的 `<spine>` 部分。
  static List<String> _parseSpine(XmlDocument opfDoc, Map<String, String> manifest) {
    final spineHrefs = <String>[];
    // 找到 <spine> 标签内的所有 <itemref> 元素。
    opfDoc.findAllElements('itemref').forEach((node) {
      final idref = node.getAttribute('idref');
      // 在清单中查找 ID 以获取实际的文件 href。
      if (idref != null && manifest.containsKey(idref)) {
        spineHrefs.add(manifest[idref]!);
      } else {
        print('[WARN] 在清单中未找到 idref="$idref" 的 spine 项目。');
      }
    });
    return spineHrefs;
  }

  /// 从 OPF 元数据中找到封面图片
  static String? _findCoverImageHref(XmlDocument opfDoc, Map<String, String> manifest) {
    // 方法 1: EPUB 3 标准识别封面图片的方式。
    try {
      final coverItem = opfDoc.findAllElements('item').firstWhere(
            (node) => node.getAttribute('properties')?.contains('cover-image') ?? false,
          );
      print('[INFO] 通过 EPUB 3 "properties" 属性找到封面图片。');
      return coverItem.getAttribute('href');
    } catch (e) {
      /* 未找到，平稳地尝试下一种方法 */
    }

    // 方法 2: 较旧的 EPUB 2 标准。
    try {
      final meta = opfDoc.findAllElements('meta').firstWhere(
            (node) => node.getAttribute('name') == 'cover',
          );
      final coverId = meta.getAttribute('content');
      if (coverId != null && manifest.containsKey(coverId)) {
        print('[INFO] 通过 EPUB 2 <meta> 标签找到封面图片。');
        return manifest[coverId];
      }
    } catch (e) {
      /* 未找到 */
    }

    // 如果两种方法都失败，则未找到封面。
    return null;
  }

  /// 从 `META-INF/container.xml` 中找到 `.opf` 文件的路径。
  static String _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('EPUB 验证错误: 未找到 META-INF/container.xml');
    final content = utf8.decode(containerFile.content as List<int>);
    final doc = XmlDocument.parse(content);
    // 第一个 '<rootfile>' 元素的 'full-path' 属性指向 .opf 文件。
    return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
  }

  /// 解析 OPF 文档的 `<manifest>` 部分。
  static Map<String, String> _parseManifest(XmlDocument opfDoc) {
    final manifest = <String, String>{};
    opfDoc.findAllElements('item').forEach((node) {
      final id = node.getAttribute('id');
      final href = node.getAttribute('href');
      if (id != null && href != null) {
        // 规范化路径分隔符并解码 URI 编码的字符（例如, %20 代表空格）。
        final normalizedHref = href.replaceAll('\\', '/');
        manifest[id] = Uri.decodeComponent(normalizedHref);
      }
    });
    return manifest;
  }

  /// 解析 `.ncx` (目录) 文件。
  static List<({String title, String srcFile, String? anchor})> _parseNcx(ArchiveFile ncxFile) {
    final navPoints = <({String title, String srcFile, String? anchor})>[];
    final content = utf8.decode(ncxFile.content as List<int>);
    final doc = XmlDocument.parse(content);

    // 找到所有定义 TOC 条目的 <navPoint> 元素。
    doc.findAllElements('navPoint').forEach((node) {
      try {
        final srcNode = node.findElements('content').firstOrNull;
        final labelNode = node.findElements('navLabel').firstOrNull?.findElements('text').firstOrNull;

        if (srcNode != null && labelNode != null) {
          final src = srcNode.getAttribute('src') ?? '';
          final title = labelNode.innerText.trim();

          // 仅添加有效的条目。
          if (src.isNotEmpty && title.isNotEmpty) {
            // 'src' 可能像 "chapter1.xhtml#section2"。我们需要将它们分开。
            final parts = src.split('#');
            // 规范化路径并解码 URI 组件。
            final normalizedSrc = Uri.decodeComponent(parts[0]).replaceAll('\\', '/');
            final anchor = parts.length > 1 ? parts[1] : null;
            navPoints.add((title: title, srcFile: normalizedSrc, anchor: anchor));
          }
        }
      } catch (e) {
        // 记录错误但继续解析其他 navPoints。
        print('[ERROR] 无法解析 NCX 文件中的一个 <navPoint> 元素: $e');
      }
    });
    return navPoints;
  }
}