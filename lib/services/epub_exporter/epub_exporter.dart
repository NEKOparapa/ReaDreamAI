// lib/services/epub_exporter/epub_exporter.dart

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:file_picker/file_picker.dart';

import '../../models/book.dart';

class EpubExporter {
  static Future<void> exportBook(Book book) async {
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出书籍',
      fileName: '${book.title}.epub',
      allowedExtensions: ['epub'],
    );

    if (outputPath == null) return;

    try {
      if (book.fileType == 'txt') {
        await _exportTxtAsEpub(book, outputPath);
      } else if (book.fileType == 'epub') {
        await _exportEpub(book, outputPath);
      }
    } catch (e) {
      print('导出过程出现错误: $e');
      if (e is Error) {
        print(e.stackTrace);
      }
      throw Exception('导出失败: $e');
    }
  }

  static Future<void> _exportTxtAsEpub(Book book, String outputPath) async {
    final archive = Archive();
    
    // [修复] 统一使用 utf8.encode() 转换字符串为字节
    final mimetypeContent = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile.noCompress(
      'mimetype', 
      mimetypeContent.length, 
      mimetypeContent
    ));
    
    final containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    
    archive.addFile(ArchiveFile(
      'META-INF/container.xml',
      utf8.encode(containerXml).length,
      utf8.encode(containerXml)
    ));
    
    final opfContent = await _buildOpfContent(book);
    archive.addFile(ArchiveFile(
      'OEBPS/content.opf',
      utf8.encode(opfContent).length,
      utf8.encode(opfContent)
    ));
    
    final ncxContent = _buildNcxContent(book);
    archive.addFile(ArchiveFile(
      'OEBPS/toc.ncx',
      utf8.encode(ncxContent).length,
      utf8.encode(ncxContent)
    ));
    
    int chapterIndex = 1;
    for (final chapter in book.chapters) {
      final htmlContent = _buildChapterHtml(chapter);
      archive.addFile(ArchiveFile(
        'OEBPS/chapter$chapterIndex.html',
        utf8.encode(htmlContent).length,
        utf8.encode(htmlContent)
      ));
      chapterIndex++;
    }
    
    await _addIllustrationsToArchive(book, archive);
    
    final cssContent = _buildCssContent();
    // [修复] 统一使用 utf8.encode() 转换字符串为字节
    final cssBytes = utf8.encode(cssContent);
    archive.addFile(ArchiveFile(
      'OEBPS/styles.css',
      cssBytes.length,
      cssBytes
    ));
    
    final epubData = ZipEncoder().encode(archive);
    if (epubData != null) {
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  static Future<void> _exportEpub(Book book, String outputPath) async {
    final originalFile = File(book.originalPath);
    final archive = ZipDecoder().decodeBytes(await originalFile.readAsBytes());
    
    final opfPath = _findOpfPath(archive);
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('找不到 OPF 文件');
    
    final opfContent = utf8.decode(opfFile.content as List<int>);
    final opfDoc = XmlDocument.parse(opfContent);
    
    await _modifyEpubHtmlFiles(book, archive, opfDoc, opfPath);
    
    _updateOpfWithIllustrations(book, opfDoc);
    
    final updatedOpfContent = opfDoc.toXmlString(pretty: true);
    archive.files.removeWhere((file) => file.name == opfPath);
    archive.addFile(ArchiveFile(
      opfPath,
      utf8.encode(updatedOpfContent).length,
      utf8.encode(updatedOpfContent)
    ));
    
    await _addIllustrationsToArchive(book, archive);
    
    final epubData = ZipEncoder().encode(archive);
    if (epubData != null) {
      await File(outputPath).writeAsBytes(epubData);
    }
  }

  static Future<void> _modifyEpubHtmlFiles(
    Book book, 
    Archive archive, 
    XmlDocument opfDoc, 
    String opfPath
  ) async {
    final manifest = _parseManifest(opfDoc);
    final spine = _parseSpine(opfDoc);
    
    for (final itemIdref in spine) {
      final sourceFile = manifest[itemIdref];
      if (sourceFile == null) continue;
      
      final chapterFilePath = p.join(p.dirname(opfPath), sourceFile).replaceAll('\\', '/');
      final chapterFile = archive.findFile(chapterFilePath);
      if (chapterFile == null) continue;
      
      final chapter = book.chapters.firstWhere(
        (ch) => ch.sourceFile.contains(p.basename(sourceFile)),
        orElse: () => ChapterStructure(title: "Unknown", sourceFile: "", lines: [])
      );
      if (chapter.lines.isEmpty && chapter.title == "Unknown") continue;
      
      final chapterHtml = utf8.decode(chapterFile.content as List<int>);
      final modifiedHtml = _modifyHtmlContent(chapterHtml, chapter);
      
      archive.files.removeWhere((file) => file.name == chapterFilePath);
      archive.addFile(ArchiveFile(
        chapterFilePath,
        utf8.encode(modifiedHtml).length,
        utf8.encode(modifiedHtml)
      ));
    }
  }

  static String _modifyHtmlContent(String html, ChapterStructure chapter) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return html;
    
    final textNodes = _findTextNodes(body);
    
    for (final line in chapter.lines) {
      final nodesToProcess = textNodes.where((node) => node.text.contains(line.originalContent)).toList();

      for (final node in nodesToProcess) {
        final parent = node.parent;
        if (parent == null) continue;

        if (line.illustrationPaths != null && line.illustrationPaths.isNotEmpty) {
          for (final imagePath in line.illustrationPaths) {
            final imageName = p.basename(imagePath);
            final imgElement = html_dom.Element.html(
              '<div style="text-align: center; margin: 1em 0;">'
              '<img src="../images/$imageName" alt="Illustration" '
              'style="max-width: 100%; height: auto;" />'
              '</div>'
            );
            if (parent.parent != null && node == parent.nodes.first) {
              parent.parent!.insertBefore(imgElement, parent);
            } else {
               parent.insertBefore(imgElement, node);
            }
          }
        }

        if (line.translatedText != null && line.translatedText!.isNotEmpty) {
           node.text = node.text.replaceFirst(line.originalContent, line.translatedText!);
        }
      }
    }
    
    return document.outerHtml;
  }


  static List<html_dom.Text> _findTextNodes(html_dom.Element element) {
    final textNodes = <html_dom.Text>[];
    
    void traverse(html_dom.Node node) {
      if (node is html_dom.Text && node.text.trim().isNotEmpty) {
        textNodes.add(node);
      } else if (node is html_dom.Element) {
        node.nodes.forEach(traverse);
      }
    }
    
    traverse(element);
    return textNodes;
  }

  static Future<void> _addIllustrationsToArchive(Book book, Archive archive) async {
    final imagePaths = <String>{};
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        if (line.illustrationPaths != null) {
          imagePaths.addAll(line.illustrationPaths);
        }
      }
    }

    for (final imagePath in imagePaths) {
      final imageFile = File(imagePath);
      if (await imageFile.exists()) {
        final imageData = await imageFile.readAsBytes();
        archive.addFile(ArchiveFile(
          'OEBPS/images/${p.basename(imagePath)}',
          imageData.length,
          imageData
        ));
      }
    }
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
        manifest[id] = href;
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

  static void _updateOpfWithIllustrations(Book book, XmlDocument opfDoc) {
    final manifest = opfDoc.findAllElements('manifest').first;
    final existingImages = manifest.findAllElements('item')
      .where((item) => item.getAttribute('media-type')?.startsWith('image/') ?? false)
      .map((item) => item.getAttribute('href'))
      .toSet();

    final imagePaths = <String>{};
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        if (line.illustrationPaths != null) {
          imagePaths.addAll(line.illustrationPaths);
        }
      }
    }

    int imageId = existingImages.length + 1;
    for (final imagePath in imagePaths) {
      final relativePath = 'images/${p.basename(imagePath)}';
      if (!existingImages.contains(relativePath)) {
        final imageExt = p.extension(imagePath).replaceAll('.', '');
        manifest.children.add(XmlElement(XmlName('item'), [
          XmlAttribute(XmlName('id'), 'image_$imageId'),
          XmlAttribute(XmlName('href'), relativePath),
          XmlAttribute(XmlName('media-type'), 'image/$imageExt'),
        ]));
        imageId++;
      }
    }
  }

  static Future<String> _buildOpfContent(Book book) async {
    final uuid = 'urn:uuid:${book.id}';
    final timestamp = DateTime.now().toIso8601String();
    
    String manifestItems = '';
    String spineItems = '';
    
    int chapterIndex = 1;
    for (final chapter in book.chapters) {
      manifestItems += '<item id="chapter$chapterIndex" href="chapter$chapterIndex.html" media-type="application/xhtml+xml"/>\n';
      spineItems += '<itemref idref="chapter$chapterIndex"/>\n';
      chapterIndex++;
    }
    
    int imageId = 1;
    final allImagePaths = <String>{};
    for (final chapter in book.chapters) {
      for (final line in chapter.lines) {
        if (line.illustrationPaths != null) {
          for (final imagePath in line.illustrationPaths) {
             allImagePaths.add(imagePath);
          }
        }
      }
    }

    for (final imagePath in allImagePaths) {
      final imageName = p.basename(imagePath);
      final imageExt = p.extension(imagePath).replaceAll('.', '');
      manifestItems += '<item id="image_$imageId" href="images/$imageName" media-type="image/$imageExt"/>\n';
      imageId++;
    }
    
    return '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="uuid-id">$uuid</dc:identifier>
    <dc:title>${book.title}</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:creator>EPUB Exporter</dc:creator>
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

  static String _buildNcxContent(Book book) {
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

  static String _buildChapterHtml(ChapterStructure chapter) {
    String content = '';
    
    for (final line in chapter.lines) {
      final text = line.translatedText?.isNotEmpty == true ? line.translatedText! : line.text;
      content += '<p>${text.replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</p>\n';
      
      if (line.illustrationPaths != null && line.illustrationPaths.isNotEmpty) {
        for (final imagePath in line.illustrationPaths) {
          final imageName = p.basename(imagePath);
          content += '<div style="text-align: center; margin: 1em 0;">'
                    '<img src="images/$imageName" alt="Illustration" style="max-width: 100%; height: auto;" />'
                    '</div>\n';
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

  static String _buildCssContent() {
    return '''
body {
  font-family: serif;
  line-height: 1.6;
  margin: 1em;
  padding: 0;
}

h1 {
  font-size: 1.5em;
  text-align: center;
  margin-bottom: 1em;
}

p {
  text-indent: 2em;
  margin: 0.5em 0;
}
''';
  }
}