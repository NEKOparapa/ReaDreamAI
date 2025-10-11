// lib/services/drawing_service/platforms/novelai_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img; // 用于图像处理
import 'package:archive/archive.dart'; // 用于解压ZIP

import '../../../base/log/log_service.dart';
import '../../../base/api_model.dart';
import '../drawing_platform.dart';

/// NovelAI 平台的具体实现。
class NovelaiPlatform implements DrawingPlatform {
  final http.Client client;

  NovelaiPlatform({required this.client});

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
  }) async {
    // 1. 如果有参考图，则执行图生图任务
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      LogService.instance.info('[NovelAI] 检测到参考图，准备执行图生图任务...');
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
    }

    // 2. 否则，执行文生图任务
    LogService.instance.info('[NovelAI] 🚀 正在执行文生图 (Text-to-Image) 任务...');
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

  /// 文生图任务
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig,
  }) async {
    final payload = _buildPayload(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      count: count,
      apiConfig: apiConfig,
      referenceImageBase64: null, // 文生图没有参考图
    );
    return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
  }

  /// 图生图任务
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
    try {
      // 预处理参考图：读取、调整尺寸并重新编码为Base64
      final processedBase64 = await _preprocessReferenceImage(referenceImagePath);
      if (processedBase64 == null) {
        throw Exception('参考图预处理失败。');
      }

      final payload = _buildPayload(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        count: count,
        apiConfig: apiConfig,
        referenceImageBase64: processedBase64,
      );
      return _executeGenerationRequest(payload: payload, saveDir: saveDir, apiConfig: apiConfig);
    } catch (e, s) {
      LogService.instance.error('[NovelAI] 图生图任务失败', e, s);
      return null;
    }
  }

  /// 构建发送给 NovelAI API 的请求体 (Payload)
  Map<String, dynamic> _buildPayload({
    required String positivePrompt,
    required String negativePrompt,
    required int width,
    required int height,
    required int count,
    required ApiModel apiConfig, 
    String? referenceImageBase64,
  }) {
    
    // 基础参数，参考Python代码并精简
    final parameters = {
      "width": width,
      "height": height,
      "n_samples": count,
      "negative_prompt": negativePrompt, // V3/旧版负向提示词也保留一下
      // V4 提示词结构
      "v4_prompt": {
        "caption": {"base_caption": positivePrompt, "char_captions": []},
        "use_coords": false,
        "use_order": true
      },
      "v4_negative_prompt": {
        "caption": {"base_caption": negativePrompt, "char_captions": []},
        "legacy_uc": false
      },
    };

    // 如果是图生图，添加参考图相关参数
    if (referenceImageBase64 != null) {
      parameters['director_reference_images'] = [referenceImageBase64];
      parameters['director_reference_descriptions'] = [{
        "caption": {"base_caption": "character&style", "char_captions": []},
        "legacy_uc": false
      }];
      parameters['director_reference_information_extracted'] = [1];
      parameters['director_reference_strength_values'] = [1.0];
      parameters['add_original_image'] = false; // 图生图时通常设为false
    } else {
      parameters['add_original_image'] = true;
    }

    return {
      "model": apiConfig.model.isNotEmpty ? apiConfig.model : "nai-diffusion-4-5-full", // 优先使用配置的模型，否则使用默认模型
      "action": "generate",
      "parameters": parameters,
    };
  }

  /// 执行API请求并处理响应
  Future<List<String>?> _executeGenerationRequest({
    required Map<String, dynamic> payload,
    required String saveDir,
    required ApiModel apiConfig,
  }) async {
    const endpoint = 'https://image.novelai.net/ai/generate-image';
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}"
    };

    try {
      LogService.instance.info('[NovelAI] 正在发送请求到 NovelAI API...');
      final response = await client.post(
        Uri.parse(endpoint),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode != 200) {
        throw Exception('NovelAI API 请求失败 (${response.statusCode}): ${response.body}');
      }
      
      LogService.instance.info('[NovelAI] 成功获取响应，正在解压并保存图片...');
      // NovelAI返回的是一个zip文件，需要解压
      return _saveImagesFromZipResponse(response.bodyBytes, saveDir);

    } catch (e, s) {
      LogService.instance.error('[NovelAI] 请求或处理 NovelAI API 时发生严重错误', e, s);
      return null;
    }
  }

  /// 从ZIP响应中解压并保存图片
  Future<List<String>> _saveImagesFromZipResponse(List<int> zipBytes, String saveDir) async {
    final savedImagePaths = <String>[];
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      await Directory(saveDir).create(recursive: true);

      for (final file in archive) {
        if (file.isFile) {
          final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
          final outputStream = File(imagePath);
          await outputStream.writeAsBytes(file.content as List<int>);
          savedImagePaths.add(imagePath);
          LogService.instance.success('[NovelAI] 图片已保存到: $imagePath');
        }
      }
    } catch (e, s) {
      LogService.instance.error('[NovelAI] 解压或保存图片时出错', e, s);
    }
    return savedImagePaths;
  }
  
  /// 预处理参考图：读取、调整尺寸、重新编码为Base64
  Future<String?> _preprocessReferenceImage(String imagePath) async {
    LogService.instance.info('[NovelAI] 🖼️  正在预处理参考图: $imagePath');
    try {
      // 1. 读取图片文件字节
      final file = File(imagePath);
      if (!await file.exists()) {
        LogService.instance.warn('[NovelAI] 参考图文件不存在: $imagePath');
        return null;
      }
      final imageBytes = await file.readAsBytes();

      // 2. 解码图片
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        LogService.instance.warn('[NovelAI] 无法解码图片: $imagePath');
        return null;
      }

      // 3. 计算符合 NovelAI 要求的最佳尺寸
      final (finalWidth, finalHeight) = _calculateNovelaiReferenceDimensions(image.width, image.height);
      
      // 4. 调整图片尺寸
      final resizedImage = img.copyResize(
        image,
        width: finalWidth,
        height: finalHeight,
        interpolation: img.Interpolation.cubic, // 使用高质量的插值算法
      );
      
      // 5. 将调整后的图片编码为 PNG 格式的字节
      final pngBytes = img.encodePng(resizedImage, level: 0); // level: 0 对应 python 的 compress_level=0

      // 6. 将 PNG 字节编码为 Base64 字符串
      final base64String = base64Encode(pngBytes);
      LogService.instance.info('[NovelAI] 参考图预处理完成，新尺寸: ${finalWidth}x$finalHeight。');
      return base64String;

    } catch (e, s) {
      LogService.instance.error('[NovelAI] 预处理参考图时出错', e, s);
      return null;
    }
  }

  /// 根据原始宽高计算 NovelAI 推荐的参考图尺寸
  (int, int) _calculateNovelaiReferenceDimensions(int width, int height) {
    const double aspectRatioThreshold = 1.1;
    final double originalAspectRatio = width / height;

    double targetAspectRatio;
    int targetPixels;

    if (1 / aspectRatioThreshold < originalAspectRatio && originalAspectRatio < aspectRatioThreshold) {
      // 类方形图片
      targetAspectRatio = 1.0;
      targetPixels = 2166784; // 1472*1472
    } else if (originalAspectRatio >= aspectRatioThreshold) {
      // 横屏图片
      targetAspectRatio = 1.5;
      targetPixels = 1572864; // 1536*1024
    } else {
      // 竖屏图片
      targetAspectRatio = 2 / 3;
      targetPixels = 1572864; // 1024*1536
    }

    final double idealHeight = sqrt(targetPixels / targetAspectRatio);
    final double idealWidth = idealHeight * targetAspectRatio;

    // 向下取整到最近的64的倍数
    final int finalWidth = (idealWidth ~/ 64) * 64;
    final int finalHeight = (idealHeight ~/ 64) * 64;

    return (finalWidth, finalHeight);
  }
}