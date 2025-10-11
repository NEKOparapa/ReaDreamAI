// lib/services/drawing_service/platforms/volcengine_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../base/log/log_service.dart';
import '../../../base/api_model.dart';
import '../drawing_platform.dart';

/// 火山引擎（Volcengine）平台的具体实现。
class VolcenginePlatform implements DrawingPlatform {
  final http.Client client;

  VolcenginePlatform({required this.client});


  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    String? referenceImagePath, // 参考图的路径或URL（可选）
  }) async {
    // 1. 判断是否有参考图，并进行预处理
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      String? imageParameter;
      // 判断参考图是网络URL还是本地文件路径
      if (referenceImagePath.startsWith('http://') || referenceImagePath.startsWith('https://')) {
        imageParameter = referenceImagePath; // 如果是URL，直接使用
        LogService.instance.info('[火山引擎] 检测到URL参考图，准备执行图生图任务...');
      } else {
        // 如果是本地路径，则将其编码为Base64
        imageParameter = await _encodeLocalImageToBase64(referenceImagePath); 
        if (imageParameter != null) {
          LogService.instance.info('[火山引擎] 检测到本地参考图，准备执行图生图任务...');
        }
      }

      // 2. 如果参考图处理成功，则调用图生图（Image-to-Image）方法
      if (imageParameter != null) {
        return _generateImageToImage(
          positivePrompt: positivePrompt,
          negativePrompt: negativePrompt,
          saveDir: saveDir,
          count: count,
          width: width,
          height: height,
          apiConfig: apiConfig,
          imageParameter: imageParameter, // 传入处理好的参考图数据（URL或Base64）
        );
      } else {
         // 如果参考图处理失败，记录警告并退回到文生图模式
         LogService.instance.warn('[火山引擎] 参考图处理失败，将退回为文生图任务。');
      }
    }
    
    // 3. 如果没有提供参考图或参考图处理失败，则调用文生图（Text-to-Image）方法
    LogService.instance.info('[火山引擎] 🚀 正在执行文生图 (Text-to-Image) 任务...');
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



  /// 文生图任务。
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
  }) async {
    // 构建API请求的JSON载荷
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      "model": apiConfig.model.isNotEmpty ? apiConfig.model : "doubao-seedream-3-0-t2i-250415", // 模型ID
      "size": "${width}x${height}", // 图像尺寸
      "n": count, // 生成数量
      "response_format": "b64_json", // 返回Base64编码的图像数据
      "watermark": false, // 不添加水印
    };

    // 执行通用的API请求逻辑
    return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
  }


  /// 图生图任务。
  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    required String imageParameter, // 接收URL或Base64格式的参考图数据
  }) async {
    // 构建API请求的JSON载荷
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      // 图生图建议使用支持该功能的模型
      "model": apiConfig.model.isNotEmpty ? apiConfig.model : "doubao-seedream-4-0-250828",
      "size": "${width}x${height}",
      "n": count,
      "response_format": "b64_json", 
      "watermark": false,
      'image': imageParameter, // 传入参考图数据
    };

    // 执行通用的API请求逻辑
    return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
  }


  /// API发送生成请求
  Future<List<String>?> _executeGenerationRequest({
    required Map<String, dynamic> payload,
    required String saveDir,
    required ApiModel apiConfig,
  }) async {
    // API的固定基础URL和端点
    const baseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
    final endpoint = Uri.parse('$baseUrl/images/generations');
    // 设置请求头，包括认证信息
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}"
    };

    try {
      // 发送POST请求，并设置180秒的超时时间
      final apiResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      // 检查响应状态码，如果不是200（成功），则抛出异常
      if (apiResponse.statusCode != 200) {
        throw Exception('火山引擎 API 请求失败 (${apiResponse.statusCode}): ${apiResponse.body}');
      }

      // 解码响应体，并调用方法保存图片
      final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
      return _saveImagesFromResponse(responseData, saveDir);

    } catch (e, s) { // 捕获包括网络、超时、解码等所有可能的错误
      LogService.instance.error('[火山引擎] 请求或处理火山引擎API时发生严重错误', e, s);
      return null;
    }
  }

  /// 将API响应中的Base64数据解码并保存为图片文件。
  Future<List<String>?> _saveImagesFromResponse(Map<String, dynamic> responseData, String saveDir) async {
    final dataList = responseData['data'] as List?;
    // 检查响应中是否包含图像数据
    if (dataList == null || dataList.isEmpty) {
      throw Exception('火山引擎 API 未返回图像数据。响应: ${jsonEncode(responseData)}');
    }

    LogService.instance.info('[火山引擎] 成功获取图像 Base64 数据，准备解码并保存...');
    // 并行处理所有图片数据
    final saveFutures = dataList.map((item) async {
      final b64Json = (item as Map<String, dynamic>)['b64_json'] as String?;
      if (b64Json != null && b64Json.isNotEmpty) {
        try {
          // 解码Base64字符串为字节数据
          final imageBytes = base64Decode(b64Json);
          // 生成唯一的文件名并拼接完整路径
          final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
          // 确保保存目录存在
          await Directory(saveDir).create(recursive: true);
          // 将字节数据写入文件
          await File(imagePath).writeAsBytes(imageBytes);
          LogService.instance.success('[火山引擎] 图片已保存到: $imagePath');
          return imagePath;
        } catch (e, s) {
          LogService.instance.error('[火山引擎] 保存单张图片时出错', e, s);
          return null; // 单个文件保存失败不影响其他文件
        }
      }
      return null;
    });

    // 等待所有保存操作完成，并过滤掉失败的结果（null）
    final imagePaths = (await Future.wait(saveFutures)).whereType<String>().toList();
    // 如果至少有一张图片保存成功，则返回路径列表，否则返回null
    return imagePaths.isNotEmpty ? imagePaths : null;
  }
  
  /// 将本地图片文件路径转换为符合火山API要求的Base64
  Future<String?> _encodeLocalImageToBase64(String localPath) async {
    LogService.instance.info('[火山引擎] 🖼️  正在编码本地参考图为 Base64: $localPath');
    try {
      final file = File(localPath);
      // 检查文件是否存在
      if (!await file.exists()) {
        LogService.instance.warn('[火山引擎] 本地参考图文件不存在: $localPath');
        return null;
      }
      
      // 读取文件内容为字节
      final imageBytes = await file.readAsBytes();
      // 将字节编码为Base64字符串
      final base64Image = base64Encode(imageBytes);
      // 获取文件扩展名作为图片格式（如 'png', 'jpeg'）
      final extension = p.extension(localPath).replaceFirst('.', '').toLowerCase();
      
      // 拼接成Data URI格式
      final dataUri = 'data:image/$extension;base64,$base64Image';
      LogService.instance.info('[火山引擎] Base64 编码完成。');
      return dataUri;

    } catch (e, s) {
      LogService.instance.error('[火山引擎] 读取或编码本地参考图时出错', e, s);
      return null;
    }
  }
}