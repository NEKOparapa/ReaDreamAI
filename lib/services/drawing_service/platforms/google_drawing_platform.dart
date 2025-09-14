// lib/services/drawing_service/platforms/google_drawing_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; 
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

// 辅助类，用于封装图片数据和 MIME 类型
class _ImageData {
  final Uint8List bytes;
  final String mimeType;

  _ImageData({required this.bytes, required this.mimeType});
}

/// Google Gemini 平台的具体实现。
class GoogleDrawingPlatform implements DrawingPlatform {
  final http.Client client;
  final ApiModel apiConfig;

  GoogleDrawingPlatform({required this.client, required this.apiConfig});

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    String? referenceImagePath,
  }) async {
    if (count > 1) {
      print('[Google Gemini] ℹ️ 注意: Gemini API 不支持单次请求生成多张图片。');
    }
    print('[Google Gemini] ℹ️ 注意: Gemini API 当前忽略 `negativePrompt`, `width`, `height` 参数。');

    final List<Map<String, dynamic>> parts = [
      {"text": positivePrompt},
    ];

    // 处理参考图
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 处理 URL 和本地路径
      final imagePart = await _createImagePart(referenceImagePath);
      if (imagePart != null) {
        parts.add(imagePart);
        print('[Google Gemini] 🚀 正在执行文+图生图 (Image-to-Image) 任务...');
      } else {
        print('[Google Gemini] ⚠️ 参考图处理失败，将退回为文生图任务。');
      }
    } else {
      print('[Google Gemini] 🚀 正在执行文生图 (Text-to-Image) 任务...');
    }
    
    try {
      final imagePath = await _executeGenerationRequest(parts, saveDir);
      if (imagePath != null) {
        print('[Google Gemini] ✅ 图片生成成功。');
        return [imagePath];
      } else {
         print('[Google Gemini] ❌ 图片生成失败，未收到有效数据。');
         return null;
      }
    } catch (e) {
      print('[Google Gemini] ❌ 图片生成时发生严重错误: $e');
      return null;
    }
  }

  // 执行实际的生成请求
  Future<String?> _executeGenerationRequest(List<Map<String, dynamic>> parts, String saveDir) async {
    final endpoint = Uri.parse('${apiConfig.url}/models/${apiConfig.model}:generateContent');
    final headers = {
      "Content-Type": "application/json",
      "x-goog-api-key": apiConfig.apiKey,
    };
    final payload = {
      "contents": [{"parts": parts}]
    };

    final apiResponse = await client.post(
      endpoint,
      headers: headers,
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 180));

    if (apiResponse.statusCode != 200) {
      throw Exception('Google Gemini API 请求失败 (状态码: ${apiResponse.statusCode}): ${apiResponse.body}');
    }

    final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
    final b64Json = responseData['candidates']?[0]?['content']?['parts']?[0]?['inlineData']?['data'] as String?;

    if (b64Json == null || b64Json.isEmpty) {
      print('[Google Gemini] ⚠️ API 未返回有效的图像数据。响应: ${jsonEncode(responseData)}');
      return null;
    }

    return _saveImageFromBase64(b64Json, saveDir);
  }

  Future<String> _saveImageFromBase64(String b64Json, String saveDir) async {
    final imageBytes = base64Decode(b64Json);
    final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
    await Directory(saveDir).create(recursive: true);
    await File(imagePath).writeAsBytes(imageBytes);
    print('[Google Gemini] ✅ 图片已保存到: $imagePath');
    return imagePath;
  }
  

  Future<Map<String, dynamic>?> _createImagePart(String pathOrUrl) async {
    print('[Google Gemini] 🖼️  正在处理参考图: $pathOrUrl');
    try {
      // 调用新的辅助方法获取图片数据
      final imageData = await _getImageData(pathOrUrl);
      if (imageData == null) {
        return null; // _getImageData 内部会打印失败日志
      }

      final base64Image = base64Encode(imageData.bytes);
      
      return {
        "inline_data": {
          "mime_type": imageData.mimeType,
          "data": base64Image,
        }
      };
    } catch (e) {
      print('[Google Gemini] ❌  创建图片 part 时发生未知错误: $e');
      return null;
    }
  }

  // 辅助方法，用于适配本地路径和云端 URL
  Future<_ImageData?> _getImageData(String pathOrUrl) async {
    final uri = Uri.tryParse(pathOrUrl);
    // 判断是 URL 还是本地路径
    if (uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'))) {
      // --- 处理 URL ---
      try {
        print('[Google Gemini] 📥  检测到 URL，正在下载图片...');
        final response = await client.get(uri).timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) {
          final contentType = response.headers['content-type'] ?? 'image/jpeg';
          // 提取主MIME类型，例如从 'image/jpeg; charset=utf-8' 中得到 'image/jpeg'
          final mimeType = contentType.split(';')[0].trim(); 
          return _ImageData(bytes: response.bodyBytes, mimeType: mimeType);
        } else {
          print('[Google Gemini] ❌  下载图片失败 (状态码: ${response.statusCode})');
          return null;
        }
      } catch (e) {
        print('[Google Gemini] ❌  下载图片时发生网络错误: $e');
        return null;
      }
    } else {
      // --- 处理本地文件路径 ---
      try {
        print('[Google Gemini] 📁  检测到本地路径，正在读取文件...');
        final file = File(pathOrUrl);
        if (!await file.exists()) {
          print('[Google Gemini] ⚠️  警告：本地参考图文件不存在: $pathOrUrl');
          return null;
        }

        final imageBytes = await file.readAsBytes();
        final mimeType = _getMimeTypeFromPath(pathOrUrl);
        return _ImageData(bytes: imageBytes, mimeType: mimeType);

      } catch (e) {
        print('[Google Gemini] ❌  读取本地参考图文件时出错: $e');
        return null;
      }
    }
  }

  // 辅助方法，根据文件路径推断 MIME 类型
  String _getMimeTypeFromPath(String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        print('[Google Gemini] ⚠️ 不支持的图片格式: $extension. 将默认使用 image/jpeg。');
        return 'image/jpeg';
    }
  }
}