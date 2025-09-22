// lib/services/drawing_service/platforms/google_drawing_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../base/log/log_service.dart';
import '../../../models/api_model.dart';
import '../drawing_platform.dart';

// 辅助类，封装图片的二进制数据和MIME类型
class _ImageData {
  final Uint8List bytes; // 图片的二进制数据
  final String mimeType; // 图片的MIME类型, 例如 "image/png"

  _ImageData({required this.bytes, required this.mimeType});
}

/// Google Gemini 绘图平台
class GoogleDrawingPlatform implements DrawingPlatform {
  final http.Client client; // 用于发起网络请求的http客户端
  GoogleDrawingPlatform({required this.client});


  /// 生成图像方法入口，根据有无参考图路径分发到不同的处理方法。
  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt, // 不支持
    required String saveDir,
    required int count,  // 不支持
    required int width,  // 不支持
    required int height, // 不支持
    required ApiModel apiConfig,
    String? referenceImagePath,
  }) async {
    // 根据是否存在 referenceImagePath，调用不同的私有方法
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 情况一：有图片路径，启用文+图生图
      return _generateImageToImage(
        positivePrompt: positivePrompt,
        referenceImagePath: referenceImagePath,
        saveDir: saveDir,
        apiConfig: apiConfig,
      );
    } else {
      // 情况二：没有图片路径，启用文生图
      return _generateTextToImage(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        apiConfig: apiConfig,
      );
    }
  }


  /// 处理文生图 (Text-to-Image) 的逻辑
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String saveDir,
    required ApiModel apiConfig,
  }) async {
    LogService.instance.info('[Google Gemini] 🚀 正在执行文生图 (Text-to-Image) 任务...');
    try {
      // 1. 构建请求体 (仅包含文本)
      final List<Map<String, dynamic>> parts = [
        {"text": positivePrompt},
      ];

      // 2. 执行请求并获取结果
      final imagePath = await _executeGenerationRequest(parts, saveDir, apiConfig);

      // 3. 处理并返回结果
      if (imagePath != null) {
        LogService.instance.success('[Google Gemini] ✅ 文生图成功。');
        return [imagePath];
      } else {
        LogService.instance.error('[Google Gemini] ❌ 文生图失败，API未返回有效数据。');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Google Gemini] ❌ 文生图时发生严重错误', e, s);
      return null;
    }
  }

  /// 处理文+图生图 (Image-to-Image) 的逻辑
  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String referenceImagePath,
    required String saveDir,
    required ApiModel apiConfig,
  }) async {
    LogService.instance.info('[Google Gemini] 🚀 正在执行文+图生图 (Image-to-Image) 任务...');
    try {
      // 1. 处理参考图，创建图片 part
      final imagePart = await _createImagePart(referenceImagePath);
      if (imagePart == null) {
        // 如果参考图处理失败，则中止任务，不再回退到文生图
        LogService.instance.error('[Google Gemini] ❌ 参考图处理失败，任务中止。');
        return null;
      }
      
      // 2. 构建请求体 (包含文本和图片)
      final List<Map<String, dynamic>> parts = [
        {"text": positivePrompt},
        imagePart,
      ];

      // 3. 执行请求并获取结果
      final imagePath = await _executeGenerationRequest(parts, saveDir, apiConfig);
      
      // 4. 处理并返回结果
      if (imagePath != null) {
        LogService.instance.success('[Google Gemini] ✅ 文+图生图成功。');
        return [imagePath];
      } else {
        LogService.instance.error('[Google Gemini] ❌ 文+图生图失败，API未返回有效数据。');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Google Gemini] ❌ 文+图生图时发生严重错误', e, s);
      return null;
    }
  }
  

  /// [公用] 执行实际的API生成请求
  Future<String?> _executeGenerationRequest(List<Map<String, dynamic>> parts, String saveDir, ApiModel apiConfig) async {
    // 构建请求的URL、头部和载荷
    final endpoint = Uri.parse('${apiConfig.url}/models/${apiConfig.model}:generateContent');
    final headers = {
      "Content-Type": "application/json",
      "x-goog-api-key": apiConfig.apiKey,
    };
    final payload = {
      "contents": [{"parts": parts}]
    };

    // 发起POST请求，并设置180秒超时
    final apiResponse = await client.post(
      endpoint,
      headers: headers,
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 180));

    // 检查响应状态码
    if (apiResponse.statusCode != 200) {
      // 如果请求失败，抛出异常
      throw Exception('Google Gemini API 请求失败 (状态码: ${apiResponse.statusCode}): ${apiResponse.body}');
    }

    // 解析响应数据
    final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
    // 从响应中提取Base64编码的图片数据
    final b64Json = responseData['candidates']?[0]?['content']?['parts']?[0]?['inlineData']?['data'] as String?;

    if (b64Json == null || b64Json.isEmpty) {
      // 如果API没有返回有效的图片数据，记录警告并返回null
      LogService.instance.warn('[Google Gemini] ⚠️ API 未返回有效的图像数据。响应: ${jsonEncode(responseData)}');
      return null;
    }

    // 将Base64数据保存为图片文件
    return _saveImageFromBase64(b64Json, saveDir);
  }

  /// [公用] 将Base64编码的字符串解码并保存为图片文件
  Future<String> _saveImageFromBase64(String b64Json, String saveDir) async {
    final imageBytes = base64Decode(b64Json); // 解码
    final imagePath = p.join(saveDir, '${const Uuid().v4()}.png'); // 生成唯一文件名
    await Directory(saveDir).create(recursive: true); // 确保保存目录存在
    await File(imagePath).writeAsBytes(imageBytes); // 写入文件
    LogService.instance.info('[Google Gemini] ✅ 图片已保存到: $imagePath');
    return imagePath;
  }
  
  /// [公用] 根据路径或URL创建适用于API请求的图片 "part"
  Future<Map<String, dynamic>?> _createImagePart(String pathOrUrl) async {
    LogService.instance.info('[Google Gemini] 🖼️  正在处理参考图: $pathOrUrl');
    try {
      // 调用辅助方法获取图片数据（处理URL和本地文件）
      final imageData = await _getImageData(pathOrUrl);
      if (imageData == null) {
        return null; // _getImageData 内部会记录失败日志
      }

      // 将图片二进制数据编码为Base64
      final base64Image = base64Encode(imageData.bytes);
      
      // 返回符合Gemini API格式的图片数据结构
      return {
        "inline_data": {
          "mime_type": imageData.mimeType,
          "data": base64Image,
        }
      };
    } catch (e, s) {
      LogService.instance.error('[Google Gemini] ❌  创建图片 part 时发生未知错误', e, s);
      return null;
    }
  }

  /// [公用] 辅助方法，用于从本地路径或网络URL获取图片数据
  Future<_ImageData?> _getImageData(String pathOrUrl) async {
    final uri = Uri.tryParse(pathOrUrl);
    // 判断是 URL 还是本地路径
    if (uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'))) {
      // 当图片是 URL 时，执行网络下载
      try {
        LogService.instance.info('[Google Gemini] 📥  检测到 URL，正在下载图片...');
        final response = await client.get(uri).timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) {
          final contentType = response.headers['content-type'] ?? 'image/jpeg';
          // 提取主MIME类型，例如从 'image/jpeg; charset=utf-8' 中得到 'image/jpeg'
          final mimeType = contentType.split(';')[0].trim(); 
          return _ImageData(bytes: response.bodyBytes, mimeType: mimeType);
        } else {
          LogService.instance.error('[Google Gemini] ❌  下载图片失败 (状态码: ${response.statusCode})');
          return null;
        }
      } catch (e, s) {
        LogService.instance.error('[Google Gemini] ❌  下载图片时发生网络错误', e, s);
        return null;
      }
    } else {
      // 当图片是本地路径时，读取文件
      try {
        LogService.instance.info('[Google Gemini] 📁  检测到本地路径，正在读取文件...');
        final file = File(pathOrUrl);
        if (!await file.exists()) {
          LogService.instance.warn('[Google Gemini] ⚠️  警告：本地参考图文件不存在: $pathOrUrl');
          return null;
        }

        final imageBytes = await file.readAsBytes();
        final mimeType = _getMimeTypeFromPath(pathOrUrl); // 根据文件后缀推断MIME类型
        return _ImageData(bytes: imageBytes, mimeType: mimeType);

      } catch (e, s) {
        LogService.instance.error('[Google Gemini] ❌  读取本地参考图文件时出错', e, s);
        return null;
      }
    }
  }

  /// [公用] 辅助方法，根据文件路径的后缀名推断 MIME 类型
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
        // 对于不支持或未知的格式，发出警告并使用默认值
        LogService.instance.warn('[Google Gemini] ⚠️ 不支持的图片格式: $extension. 将默认使用 image/png。');
        return 'image/png';
    }
  }
}