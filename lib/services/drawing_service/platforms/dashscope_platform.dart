// lib/services/drawing_service/platforms/dashscope_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../base/log/log_service.dart';
import '../../../base/api_model.dart';
import '../drawing_platform.dart';

/// 阿里通义千问 (Dashscope) 平台的具体实现。
class DashscopePlatform implements DrawingPlatform {
  final http.Client client;

  // 构造函数，依赖注入 http.Client 以便测试
  DashscopePlatform({required this.client});

  // 定义通义千问支持的固定分辨率及其对应的宽高比
  static const Map<String, double> _supportedRatios = {
    '1664*928': 16.0 / 9.0, // 16:9
    '1472*1140': 4.0 / 3.0, // 4:3
    '1328*1328': 1.0,       // 1:1
    '1140*1472': 3.0 / 4.0, // 3:4
    '928*1664': 9.0 / 16.0,  // 9:16
  };


  /// 生成图像方法入口。根据是否提供参考图路径，分发到不同的处理方法。
  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    String? referenceImagePath,
  }) {
    // 根据是否存在参考图，调用相应的方法
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 情况一：有图片路径，启用文+图生图
      return _generateImageToImage(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
        apiConfig: apiConfig,
        referenceImagePath: referenceImagePath,
      );
    } else {
      // 情况二：没图片路径，启用文生图
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
  }

  // =======================================================================
  // == 两种情况的具体实现 (Specific Implementations)
  // =======================================================================

  /// 处理文生图 (Text-to-Image) 任务。
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
  }) async {
    // 根据任务类型自动适配模型名称
    final adaptedModel = _getAdaptedModel(apiConfig.model, isImageToImage: false);
    
    // 更新日志，使用适配后的模型名称
    LogService.instance.info('[通义千问] 🚀 正在执行文生图 (Text-to-Image) 任务，使用模型: $adaptedModel');
    
    final content = [{"text": positivePrompt}];
    final adaptedSize = _getClosestSupportedSize(width, height);

    // 构建API请求负载 (payload)
    final payload = {
      "model": adaptedModel,
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
    
    // 调用公共的执行方法
    return _executeApiCallAndDownloadImages(
      payload: payload,
      apiConfig: apiConfig,
      saveDir: saveDir,
    );
  }

  /// 处理文+图生图 (Image-to-Image) 任务。
  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
    required String referenceImagePath,
  }) async {
    // 将参考图转换为API要求的格式
    final imageParam = await _createImageParameter(referenceImagePath);

    // 如果参考图处理失败，则退回为纯文生图
    if (imageParam == null) {
      LogService.instance.warn('[通义千问] ⚠️ 参考图处理失败，将退回为文生图任务。');
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
    
    // 根据任务类型自动适配模型名称
    final adaptedModel = _getAdaptedModel(apiConfig.model, isImageToImage: true);

    // 更新日志，使用适配后的模型名称
    LogService.instance.info('[通义千问] 🚀 正在执行文+图生图 (Image-to-Image) 任务，使用模型: $adaptedModel');

    final content = [
      {"image": imageParam},
      {"text": positivePrompt},
    ];
    final adaptedSize = _getClosestSupportedSize(width, height);
    
    // 构建API请求负载 (payload)
    final payload = {
      "model": adaptedModel,
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

    // 调用公共的执行方法
    return _executeApiCallAndDownloadImages(
      payload: payload,
      apiConfig: apiConfig,
      saveDir: saveDir,
    );
  }

  // =======================================================================
  // == 公用方法 (Common/Shared Methods)
  // =======================================================================

  // 自动转换模型的名字
  String _getAdaptedModel(String originalModel, {required bool isImageToImage}) {
    // 定义模型转换规则
    // Key: 文生图模型, Value: 对应的图生图模型
    const t2iToI2iMap = {
      'wan2.5-t2i-preview': 'wan2.5-i2i-preview',
      'qwen-image': 'qwen-image-edit',
    };
    // Key: 图生图模型, Value: 对应的文生图模型
    const i2iToT2iMap = {
      'wan2.5-i2i-preview': 'wan2.5-t2i-preview',
      'qwen-image-edit': 'qwen-image',
    };

    String adaptedModel;
    if (isImageToImage) {
      // 当前是图生图任务，检查原始模型是否在 t2i 映射中
      // 如果是，则转换为对应的 i2i 模型；否则，保持原样
      adaptedModel = t2iToI2iMap[originalModel] ?? originalModel;
    } else {
      // 当前是文生图任务，检查原始模型是否在 i2i 映射中
      // 如果是，则转换为对应的 t2i 模型；否则，保持原样
      adaptedModel = i2iToT2iMap[originalModel] ?? originalModel;
    }

    // 如果模型名称发生了变化，打印一条日志以供调试
    if (adaptedModel != originalModel) {
      LogService.instance.info(
        '[通义千问] ℹ️  模型自动转换: 从 "$originalModel" 切换到 "$adaptedModel" 以匹配任务类型 (${isImageToImage ? "文+图生图" : "文生图"})。'
      );
    }

    return adaptedModel;
  }
  
  /// 执行API调用、处理响应并下载图片的核心公共逻辑。
  Future<List<String>?> _executeApiCallAndDownloadImages({
    required Map<String, dynamic> payload,
    required ApiModel apiConfig,
    required String saveDir,
  }) async {
    final endpoint = Uri.parse('${apiConfig.url}/services/aigc/multimodal-generation/generation');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}",
    };

    try {
      // 发送POST请求，并设置180秒超时
      final apiResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      // 检查响应状态码，如果不是200 (成功)，则抛出异常
      if (apiResponse.statusCode != 200) {
        throw Exception('通义千问 API 请求失败 (${apiResponse.statusCode}): ${apiResponse.body}');
      }

      // 解码响应体
      final responseData = jsonDecode(utf8.decode(apiResponse.bodyBytes));
      
      // 从响应数据中解析出图片URL列表
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
            if (contentItem is Map<String, dynamic> && contentItem.containsKey('image')) {
              final imageUrl = contentItem['image'] as String?;
              if (imageUrl != null && imageUrl.isNotEmpty) {
                imageUrls.add(imageUrl);
              }
            }
          }
        }
      }

      // 如果没有找到任何有效的图片URL，则抛出异常
      if (imageUrls.isEmpty) {
        throw Exception('通义千问 API 返回的数据中未找到有效的图像URL。响应: ${jsonEncode(responseData)}');
      }
      
      LogService.instance.success('[通义千问] ✅ 成功获取 ${imageUrls.length} 个图像URL，准备下载...');
      
      // 并发下载所有图片
      final downloadFutures = imageUrls.map((url) => _downloadAndSaveImage(url, saveDir));

      // 等待所有下载任务完成，并过滤掉失败的null结果
      final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
      return imagePaths.isNotEmpty ? imagePaths : null;

    } catch (e, s) {
      // 捕获请求或处理过程中的任何异常，记录错误日志
      LogService.instance.error('[通义千问] ❌ 请求或处理通义千问API时发生严重错误', e, s);
      return null;
    }
  }
  
  /// 根据输入的宽高，计算并返回通义千问支持的最接近的分辨率字符串。
  String _getClosestSupportedSize(int width, int height) {
    if (height == 0) return '1328*1328';
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
    
    final originalSizeStringForCheck = "$width*$height";
    if (bestMatch != originalSizeStringForCheck) {
       LogService.instance.warn('[通义千问] ⚠️  分辨率适配：将 ${width}x$height (比例: ${targetRatio.toStringAsFixed(2)}) 调整为最接近的支持分辨率 $bestMatch');
    }

    return bestMatch;
  }
  
  /// 将参考图路径转换为API可接受的格式 (URL或Base64 Data URI)。
  Future<String?> _createImageParameter(String imagePath) async {
    LogService.instance.info('[通义千问] 🖼️  正在处理参考图: $imagePath');
    
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        LogService.instance.warn('[通义千问] ⚠️  警告：本地参考图文件不存在: $imagePath');
        return null;
      }
      
      final imageBytes = await file.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final extension = p.extension(imagePath).replaceFirst('.', '').toLowerCase();
      
      final dataUri = 'data:image/$extension;base64,$base64Image';
      LogService.instance.success('[通义千问] ✅  Base64 Data URI 编码完成。');
      return dataUri;

    } catch (e, s) {
      LogService.instance.error('[通义千问] ❌  读取或编码本地参考图时出错', e, s);
      return null;
    }
  }

  /// 从给定的URL下载图片并保存到指定目录。
  Future<String?> _downloadAndSaveImage(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
        await Directory(saveDir).create(recursive: true);
        await File(imagePath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[通义千问] ✅ 图片已保存到: $imagePath');
        return imagePath;
      } else {
        LogService.instance.error('[通义千问] ❌ 下载图片失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[通义千问] ❌ 下载图片时出错', e, s);
      return null;
    }
  }
}