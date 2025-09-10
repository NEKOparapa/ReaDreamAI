// lib/services/file_parser/epub_parser.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import '../../models/book.dart';

class EpubParser {
  /// 解析 EPUB，返回章节列表和封面路径
  static Future<({List<ChapterStructure> chapters, String? coverImagePath})> parse(String cachedPath, Directory bookCacheDir) async {
    final bytes = await File(cachedPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final opfPath = _findOpfPath(archive);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('EPUB中未找到 .opf 文件');

    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);
    final manifest = _parseManifest(opfDoc);

    // 提取并保存封面
    String? coverImagePath;
    final coverHref = _findCoverImageHref(opfDoc, manifest);
    if (coverHref != null) {
      final coverFileRelPath = p.join(p.dirname(opfPath), coverHref).replaceAll('\\', '/');
      final coverArchiveFile = archive.findFile(coverFileRelPath);
      if (coverArchiveFile != null) {
        final coverImageFile = File(p.join(bookCacheDir.path, 'cover${p.extension(coverHref)}'));
        await coverImageFile.writeAsBytes(coverArchiveFile.content as Uint8List);
        coverImagePath = coverImageFile.path;
      }
    }

    final spine = _parseSpine(opfDoc);
    final ncxPathEntry = manifest.entries.firstWhere(
      (e) => e.key.contains('ncx') || e.value.endsWith('.ncx'),
      orElse: () => const MapEntry('', ''),
    );
    final tocPath = ncxPathEntry.value;
    final tocFile = tocPath.isNotEmpty ? archive.findFile(p.join(p.dirname(opfPath), tocPath)) : null;
    final chapterTitles = (tocFile != null) ? _parseNcx(tocFile) : <String, String>{};
    final List<ChapterStructure> chapters = [];
    final htmlTagRegex = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);

    int globalLineIdCounter = 0;

    for (final itemIdref in spine) {
      final sourceFile = manifest[itemIdref];
      if (sourceFile == null) continue;

      final chapterFilePath = p.join(p.dirname(opfPath), sourceFile).replaceAll('\\', '/');
      final chapterFile = archive.findFile(chapterFilePath);
      if (chapterFile == null) continue;

      final chapterHtml = utf8.decode(chapterFile.content as List<int>);
      final rawLines = const LineSplitter().convert(chapterHtml);
      final List<LineStructure> lines = [];

      for (int i = 0; i < rawLines.length; i++) {
        final originalLine = rawLines[i];
        final cleanText = originalLine.replaceAll(htmlTagRegex, '').trim();

        if (cleanText.isNotEmpty) {
          lines.add(LineStructure(
              id: globalLineIdCounter++, // 分配ID并自增
              text: cleanText,
              lineNumberInSourceFile: i + 1,
              originalContent: originalLine));
        }
      }

      if (lines.isNotEmpty) {
        chapters.add(ChapterStructure(
          title: chapterTitles[sourceFile] ?? p.basenameWithoutExtension(sourceFile),
          sourceFile: chapterFilePath,
          lines: lines,
        ));
      }
    }

    return (chapters: chapters, coverImagePath: coverImagePath);
  }

  // EPUB 解析辅助函数
  static String? _findCoverImageHref(XmlDocument opfDoc, Map<String, String> manifest) {
    // 方法1: EPUB 3 - manifest item with properties="cover-image"
    try {
      final coverItem = opfDoc.findAllElements('item').firstWhere(
            (node) => node.getAttribute('properties')?.contains('cover-image') ?? false,
          );
      return coverItem.getAttribute('href');
    } catch (e) {
      // Not found, try method 2
    }

    // 方法2: EPUB 2 - meta tag with name="cover"
    try {
      final meta = opfDoc.findAllElements('meta').firstWhere(
            (node) => node.getAttribute('name') == 'cover',
          );
      final coverId = meta.getAttribute('content');
      if (coverId != null && manifest.containsKey(coverId)) {
        return manifest[coverId];
      }
    } catch (e) {
      // Not found
    }

    return null; // 封面未找到
  }

  static String _findOpfPath(Archive archive) {
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('META-INF/container.xml not found');
    final content = utf8.decode(containerFile.content as List<int>);
    final doc = XmlDocument.parse(content);
    return doc.findAllElements('rootfile').first.getAttribute('full-path')!;
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

  static List<String> _parseSpine(XmlDocument opfDoc) {
    final spine = <String>[];
    opfDoc.findAllElements('itemref').forEach((node) {
      final idref = node.getAttribute('idref');
      if (idref != null) {
        spine.add(idref);
      }
    });
    return spine;
  }

  static Map<String, String> _parseNcx(ArchiveFile ncxFile) {
    final titles = <String, String>{};
    final content = utf8.decode(ncxFile.content as List<int>);
    final doc = XmlDocument.parse(content);
    doc.findAllElements('navPoint').forEach((node) {
      final src = node.findElements('content').first.getAttribute('src');
      final title = node.findElements('navLabel').first.findElements('text').first.innerText;
      if (src != null) {
        final normalizedSrc = src.replaceAll('\\', '/');
        titles[Uri.decodeComponent(normalizedSrc.split('#').first)] = title;
      }
    });
    return titles;
  }
}