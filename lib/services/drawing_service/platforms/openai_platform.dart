// lib/services/drawing_service/platforms/openai_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // 需要导入
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// 自定义（OpenAI格式）平台的具体实现。
/// 支持文生图和图生图模式。
class OpenAiPlatform implements DrawingPlatform {
  final http.Client client;
  final ApiModel apiConfig;

  OpenAiPlatform({required this.client, required this.apiConfig});

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
    // 根据是否存在参考图，决定调用不同的生成方法
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      return _generateImageToImage(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
        referenceImagePath: referenceImagePath,
      );
    } else {
      return _generateTextToImage(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
      );
    }
  }

  /// 文生图 (Text-to-Image)
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
  }) async {
    print('[OpenAI - Txt2Img] 🚀 正在请求生成图像...');
    final endpoint = Uri.parse('${apiConfig.url}/images/generations');
    final headers = {
      "Authorization": "Bearer ${apiConfig.apiKey}",
      "Content-Type": "application/json",
    };

    // 构建请求体 (JSON)
    // 注意：官方OpenAI API不支持 negative_prompt，但许多兼容API支持
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      "model": apiConfig.model,
      "size": "${width}x${height}",
      "n": count,
      "response_format": "b64_json",
    };

    try {
      final response = await client
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 5));

      return _processResponse(response, saveDir);
    } catch (e, st) {
      print('[OpenAI - Txt2Img] ❌ 生成图像时发生错误: $e\n$st');
      return null;
    }
  }

  /// 图生图 (Image-to-Image)
  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required String referenceImagePath,
  }) async {
    print('[OpenAI - Img2Img] 🚀 正在请求生成图像...');
    final endpoint = Uri.parse('${apiConfig.url}/images/generations'); // 许多兼容API在同一端点支持图生图
    final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

    try {
      // 获取图片数据，自动处理URL或本地路径
      final imageBytes = await _getImageBytes(referenceImagePath);
      if (imageBytes == null) {
        throw Exception('无法获取参考图片数据。');
      }

      // 创建一个 multipart 请求
      final request = http.MultipartRequest('POST', endpoint);
      request.headers.addAll(headers);

      // 添加文本字段
      request.fields.addAll({
        'prompt': positivePrompt,
        'model': apiConfig.model,
        'size': '${width}x${height}',
        'n': count.toString(),
        'response_format': 'b64_json',
      });

      // 添加图片文件
      request.files.add(http.MultipartFile.fromBytes(
        'image', // 字段名通常是 'image'
        imageBytes,
        filename: 'reference_image.png', // 提供一个文件名
      ));
      
      // 发送请求并获取响应
      final streamedResponse = await client.send(request).timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);
      
      return _processResponse(response, saveDir);

    } catch (e, st) {
      print('[OpenAI - Img2Img] ❌ 生成图像时发生错误: $e\n$st');
      return null;
    }
  }

  /// 统一处理API响应和保存图片
  Future<List<String>?> _processResponse(http.Response response, String saveDir) async {
    if (response.statusCode != 200) {
      print('[OpenAI] ❌ API 请求失败 (${response.statusCode}): ${response.body}');
      throw Exception('OpenAI API 请求失败 (${response.statusCode}): ${response.body}');
    }

    final responseData = jsonDecode(utf8.decode(response.bodyBytes));
    final dataList = responseData['data'] as List?;

    if (dataList == null || dataList.isEmpty) {
      print('[OpenAI] ❌ API 未返回图像数据。响应: ${response.body}');
      throw Exception('OpenAI API 未返回图像数据');
    }

    print('[OpenAI] ✅ 成功获取 Base64 图像数据，准备保存...');

    await Directory(saveDir).create(recursive: true);
    final List<String> savedImagePaths = [];

    for (final item in dataList) {
      final b64Json = (item as Map<String, dynamic>)['b64_json'] as String?;
      if (b64Json != null && b64Json.isNotEmpty) {
        try {
          final imageBytes = base64Decode(b64Json);
          final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
          await File(imagePath).writeAsBytes(imageBytes);
          savedImagePaths.add(imagePath);
          print('[OpenAI] ✅ 图片已保存到: $imagePath');
        } catch (e) {
          print('[OpenAI] ❌ 解码或保存 Base64 图像时出错: $e');
        }
      } else {
        print('[OpenAI] ⚠️ 响应中未找到 b64_json 数据。');
      }
    }

    return savedImagePaths.isNotEmpty ? savedImagePaths : null;
  }

  /// 辅助方法：从本地路径或URL获取图片字节
  Future<Uint8List?> _getImageBytes(String pathOrUrl) async {
    try {
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        // 从 URL 下载
        print('[OpenAI - Util] 正在从URL下载参考图: $pathOrUrl');
        final response = await client.get(Uri.parse(pathOrUrl));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        } else {
          print('[OpenAI - Util] ❌ 下载图片失败 (${response.statusCode})');
          return null;
        }
      } else {
        // 从本地文件读取
        print('[OpenAI - Util] 正在读取本地参考图: $pathOrUrl');
        final file = File(pathOrUrl);
        if (await file.exists()) {
          return await file.readAsBytes();
        } else {
           print('[OpenAI - Util] ❌ 本地文件不存在');
          return null;
        }
      }
    } catch (e) {
      print('[OpenAI - Util] ❌ 获取图片字节时发生错误: $e');
      return null;
    }
  }
}