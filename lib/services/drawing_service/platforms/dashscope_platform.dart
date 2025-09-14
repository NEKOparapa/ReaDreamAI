// lib/services/drawing_service/platforms/dashscope_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// 阿里通义千问 (Dashscope) 平台的具体实现。
class DashscopePlatform implements DrawingPlatform {
  final http.Client client;
  final ApiModel apiConfig;

  DashscopePlatform({required this.client, required this.apiConfig});

  static const Map<String, double> _supportedRatios = {
    '1664*928': 16.0 / 9.0,
    '1472*1140': 4.0 / 3.0,
    '1328*1328': 1.0,
    '1140*1472': 3.0 / 4.0,
    '928*1664': 9.0 / 16.0,
  };

  String _getClosestSupportedSize(int width, int height) {
    if (height == 0) {
      return '1328*1328';
    }

    final targetRatio = width / height;

    String bestMatch = '1328*1328';
    double minDifference = double.maxFinite;

    for (final entry in _supportedRatios.entries) {
      final difference = (targetRatio - entry.value).abs();
      if (difference < minDifference) {
        minDifference = difference;
        bestMatch = entry.key;
      }
    }
    
    final originalSizeStringForCheck = "${width}*${height}";
    if (bestMatch != originalSizeStringForCheck) {
       print('[通义千问] ⚠️  分辨率适配：将 ${width}x${height} (比例: ${targetRatio.toStringAsFixed(2)}) 调整为最接近的支持分辨率 $bestMatch');
    }

    return bestMatch;
  }


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
    final List<Map<String, dynamic>> content = [
      {"text": positivePrompt},
    ];
    
    String model = apiConfig.model;

    // 处理参考图
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      final imageParam = await _createImageParameter(referenceImagePath);
      if (imageParam != null) {
        content.insert(0, {"image": imageParam});
        if (model == 'qwen-image') model = 'qwen-image-edit';  // 注意，这里需要切换到支持图生图的模型
        print('[通义千问] 🚀 正在执行文+图生图 (Image-to-Image) 任务，使用模型: $model');
      } else {
        print('[通义千问] ⚠️ 参考图处理失败，将退回为文生图任务。');
      }
    } else {
       print('[通义千问] 🚀 正在执行文生图 (Text-to-Image) 任务...');
    }
    
    final String adaptedSize = _getClosestSupportedSize(width, height);

    final payload = {
      "model": model,
      "input": {
        "messages": [
          {"role": "user", "content": content}
        ]
      },
      "parameters": {
        "n": count,
        "size": adaptedSize,
        "negative_prompt": negativePrompt,
      }
    };

    final endpoint = Uri.parse('${apiConfig.url}/services/aigc/multimodal-generation/generation');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}",
    };

    try {
      final apiResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      if (apiResponse.statusCode != 200) {
        throw Exception('通义千问 API 请求失败 (${apiResponse.statusCode}): ${apiResponse.body}');
      }

      final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
      
      // 【修正】API响应结构变化，重写解析逻辑
      // 根据新的JSON结构，从 output -> choices -> message -> content -> image 路径中提取URL
      final choices = responseData['output']?['choices'] as List?;
      
      if (choices == null || choices.isEmpty) {
        throw Exception('通义千问 API 未返回 choices 数据。响应: ${jsonEncode(responseData)}');
      }

      final List<String> imageUrls = [];
      for (final choice in choices) {
        final message = choice?['message'];
        final contentList = message?['content'] as List?;
        if (contentList != null) {
          for (final contentItem in contentList) {
            // 确保 contentItem 是一个 Map 并且包含 'image' 键
            if (contentItem is Map<String, dynamic> && contentItem.containsKey('image')) {
              final imageUrl = contentItem['image'] as String?;
              if (imageUrl != null && imageUrl.isNotEmpty) {
                imageUrls.add(imageUrl);
              }
            }
          }
        }
      }

      if (imageUrls.isEmpty) {
        throw Exception('通义千问 API 返回的数据中未找到有效的图像URL。响应: ${jsonEncode(responseData)}');
      }
      
      print('[通义千问] ✅ 成功获取 ${imageUrls.length} 个图像URL，准备下载...');
      // 使用提取到的imageUrls列表进行下载
      final downloadFutures = imageUrls.map((url) => _downloadAndSaveImage(url, saveDir));

      final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
      return imagePaths.isNotEmpty ? imagePaths : null;

    } catch (e) {
      print('[通义千问] ❌ 请求或处理通义千问API时发生严重错误: $e');
      return null;
    }
  }

  Future<String?> _downloadAndSaveImage(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
        await Directory(saveDir).create(recursive: true);
        await File(imagePath).writeAsBytes(response.bodyBytes);
        print('[通义千问] ✅ 图片已保存到: $imagePath');
        return imagePath;
      } else {
        print('[通义千问] ❌ 下载图片失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e) {
      print('[通义千问] ❌ 下载图片时出错: $e');
      return null;
    }
  }

  Future<String?> _createImageParameter(String imagePath) async {
    print('[通义千问] 🖼️  正在处理参考图: $imagePath');
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print('[通义千问] ⚠️  警告：本地参考图文件不存在: $imagePath');
        return null;
      }
      
      final imageBytes = await file.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final extension = p.extension(imagePath).replaceFirst('.', '').toLowerCase();
      
      final dataUri = 'data:image/$extension;base64,$base64Image';
      print('[通义千问] ✅  Base64 Data URI 编码完成。');
      return dataUri;

    } catch (e) {
      print('[通义千问] ❌  读取或编码本地参考图时出错: $e');
      return null;
    }
  }
}