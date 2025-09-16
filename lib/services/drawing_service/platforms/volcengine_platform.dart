// lib/services/drawing_service/platforms/volcengine_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// 火山引擎（Volcengine）平台的具体实现。
class VolcenginePlatform implements DrawingPlatform {
  final http.Client client;

  VolcenginePlatform({required this.client});

  // --- 公共入口方法 ---

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    String? referenceImagePath, // 接收到的参考图路径或URL
  }) async {
    // 1. 判断是否有参考图，并进行预处理
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      String? imageParameter;
      // 判断是URL还是本地路径
      if (referenceImagePath.startsWith('http://') || referenceImagePath.startsWith('https://')) {
        imageParameter = referenceImagePath; // 是URL，直接使用
        print('[火山引擎] 检测到URL参考图，准备执行图生图任务...');
      } else {
        imageParameter = await _encodeLocalImageToBase64(referenceImagePath); // 是本地路径，进行Base64编码
        if (imageParameter != null) {
          print('[火山引擎] 检测到本地参考图，准备执行图生图任务...');
        }
      }

      // 2. 如果参考图处理成功，则调用图生图方法
      if (imageParameter != null) {
        return _generateImageToImage(
          positivePrompt: positivePrompt,
          negativePrompt: negativePrompt,
          saveDir: saveDir,
          count: count,
          width: width,
          height: height,
          apiConfig: apiConfig,
          imageParameter: imageParameter, // 传入处理好的参考图数据
        );
      } else {
         print('[火山引擎] ⚠️  参考图处理失败，将退回为文生图任务。');
      }
    }
    
    // 3. 如果没有参考图或处理失败，则调用文生图方法
    print('[火山引擎] 🚀 正在执行文生图 (Text-to-Image) 任务...');
    return _generateTextToImage(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      saveDir: saveDir,
      count: count,
      width: width,
      height: height,
      apiConfig: apiConfig,
    );
  }


  // --- 私有实现方法：文生图 ---

  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
  }) async {
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      "model": apiConfig.model.isNotEmpty ? apiConfig.model : "doubao-seedream-3-0-t2i-250415",
      "size": "${width}x${height}",
      "n": count,
      "response_format": "b64_json", 
      "watermark": false,
    };

    return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
  }

  // --- 私有实现方法：图生图 ---

  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    required String imageParameter, // URL 或 Base64 Data URI
  }) async {
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      // 图生图建议使用支持该功能的模型
      "model": apiConfig.model.isNotEmpty ? apiConfig.model : "doubao-seedream-4-0-250828",
      "size": "${width}x${height}",
      "n": count,
      "response_format": "b64_json", 
      "watermark": false,
      'image': imageParameter,
    };

    return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
  }

  // --- 通用核心逻辑：执行API请求与处理 ---

  Future<List<String>?> _executeGenerationRequest({
    required Map<String, dynamic> payload,
    required String saveDir,
    required ApiModel apiConfig,
  }) async {
    const baseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
    final endpoint = Uri.parse('$baseUrl/images/generations');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}"
    };

    try {
      final apiResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      if (apiResponse.statusCode != 200) {
        throw Exception('火山引擎 API 请求失败 (${apiResponse.statusCode}): ${apiResponse.body}');
      }

      final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
      return _saveImagesFromResponse(responseData, saveDir);

    } catch (e) {
      print('[火山引擎] ❌ 请求或处理火山引擎API时发生严重错误: $e');
      return null;
    }
  }

  // --- 辅助工具方法 ---

  /// 将API响应中的Base64数据解码并保存为图片文件。
  Future<List<String>?> _saveImagesFromResponse(Map<String, dynamic> responseData, String saveDir) async {
    final dataList = responseData['data'] as List?;
    if (dataList == null || dataList.isEmpty) {
      throw Exception('火山引擎 API 未返回图像数据。响应: ${jsonEncode(responseData)}');
    }

    print('[火山引擎] ✅ 成功获取图像 Base64 数据，准备解码并保存...');
    final saveFutures = dataList.map((item) async {
      final b64Json = (item as Map<String, dynamic>)['b64_json'] as String?;
      if (b64Json != null && b64Json.isNotEmpty) {
        try {
          final imageBytes = base64Decode(b64Json);
          final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
          await Directory(saveDir).create(recursive: true);
          await File(imagePath).writeAsBytes(imageBytes);
          print('[火山引擎] ✅ 图片已保存到: $imagePath');
          return imagePath;
        } catch (e) {
          print('[火山引擎] ❌ 保存图片时出错: $e');
          return null;
        }
      }
      return null;
    });

    final imagePaths = (await Future.wait(saveFutures)).whereType<String>().toList();
    return imagePaths.isNotEmpty ? imagePaths : null;
  }
  
  /// 将本地图片文件路径转换为符合火山API要求的Base64 Data URI。
  Future<String?> _encodeLocalImageToBase64(String localPath) async {
    print('[火山引擎] 🖼️  正在编码本地参考图为 Base64: $localPath');
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        print('[火山引擎] ⚠️  警告：本地参考图文件不存在: $localPath');
        return null;
      }
      
      final imageBytes = await file.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final extension = p.extension(localPath).replaceFirst('.', '').toLowerCase();
      
      final dataUri = 'data:image/$extension;base64,$base64Image';
      print('[火山引擎] ✅  Base64 编码完成。');
      return dataUri;

    } catch (e) {
      print('[火山引擎] ❌  读取或编码本地参考图时出错: $e');
      return null;
    }
  }
}