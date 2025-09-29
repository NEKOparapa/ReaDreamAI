// lib/services/video_service/platforms/google_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../base/log/log_service.dart';
import '../../../models/api_model.dart';
import '../video_platform.dart';

/// 谷歌视频平台的具体实现
class GooglePlatform implements VideoPlatform {
  final http.Client client;

  GooglePlatform({required this.client});

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String saveDir,
    required int count,
    required String resolution,
    required int duration,
    String? referenceImagePath,
    required ApiModel apiConfig,
  }) async {
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 文+图生视频
      return await _generateWithImage(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        resolution: resolution,
        duration: duration,
        referenceImagePath: referenceImagePath,
        apiConfig: apiConfig,
      );
    } else {
      // 文生视频
      return await _generateWithTextOnly(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        resolution: resolution,
        duration: duration,
        apiConfig: apiConfig,
      );
    }
  }

  /// 文生视频方法
  Future<List<String>?> _generateWithTextOnly({
    required String positivePrompt,
    required String saveDir,
    required String resolution,
    required int duration,
    required ApiModel apiConfig,
  }) async {
    LogService.instance.info('[Google视频] 🚀 启动文生视频任务...');
    
    // 将分辨率转换为宽高
    final dimensions = _parseDimensions(resolution);
    
    final payload = {
      "prompt": positivePrompt,
      "video_length_seconds": duration,
      "width": dimensions['width'],
      "height": dimensions['height'],
      "safety_filter_level": "block_some",
    };

    final endpoint = Uri.parse('${apiConfig.url}/models/${apiConfig.model}:generateVideo?key=${apiConfig.apiKey}');
    
    try {
      final response = await client.post(
        endpoint,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return await _pollOperation(data['name'], saveDir, apiConfig);
      } else {
        throw Exception('Google视频 API 请求失败 (${response.statusCode}): ${response.body}');
      }
    } catch (e, s) {
      LogService.instance.error('[Google视频] ❌ 生成视频时发生错误', e, s);
      rethrow;
    }
  }

  /// 文+图生视频方法
  Future<List<String>?> _generateWithImage({
    required String positivePrompt,
    required String saveDir,
    required String resolution,
    required int duration,
    required String referenceImagePath,
    required ApiModel apiConfig,
  }) async {
    LogService.instance.info('[Google视频] 🚀 检测到参考图，启动文+图生视频任务...');
    
    final dimensions = _parseDimensions(resolution);
    
    // 准备图片数据
    String imageData;
    if (referenceImagePath.toLowerCase().startsWith('http')) {
      // 如果是URL，需要下载图片并转换为base64
      final imageResponse = await client.get(Uri.parse(referenceImagePath));
      if (imageResponse.statusCode == 200) {
        imageData = base64Encode(imageResponse.bodyBytes);
      } else {
        throw Exception('无法下载参考图片: $referenceImagePath');
      }
    } else {
      // 本地文件
      final file = File(referenceImagePath);
      if (!await file.exists()) {
        throw FileSystemException("参考图文件不存在", referenceImagePath);
      }
      imageData = base64Encode(await file.readAsBytes());
    }

    final payload = {
      "prompt": positivePrompt,
      "image": {"bytesBase64Encoded": imageData},
      "video_length_seconds": duration,
      "width": dimensions['width'],
      "height": dimensions['height'],
      "safety_filter_level": "block_some",
    };

    final endpoint = Uri.parse('${apiConfig.url}/models/${apiConfig.model}:generateVideoFromImage?key=${apiConfig.apiKey}');
    
    try {
      final response = await client.post(
        endpoint,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return await _pollOperation(data['name'], saveDir, apiConfig);
      } else {
        throw Exception('Google视频 API 请求失败 (${response.statusCode}): ${response.body}');
      }
    } catch (e, s) {
      LogService.instance.error('[Google视频] ❌ 生成视频时发生错误', e, s);
      rethrow;
    }
  }

  /// 轮询操作状态
  Future<List<String>?> _pollOperation(String operationName, String saveDir, ApiModel apiConfig) async {
    final endpoint = Uri.parse('${apiConfig.url}/$operationName?key=${apiConfig.apiKey}');
    
    const maxAttempts = 30; // 最大轮询次数 (30 * 10s = 5分钟)
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 10));
      
      try {
        final response = await client.get(endpoint);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['done'] == true) {
            if (data.containsKey('error')) {
              throw Exception('视频生成失败: ${data['error']['message']}');
            }
            
            final videoUri = data['response']['uri'];
            if (videoUri != null) {
              LogService.instance.success('[Google视频] ✅ 视频生成成功！');
              final filePath = await _downloadAndSaveVideo(videoUri, saveDir);
              return filePath != null ? [filePath] : null;
            }
          }
          
          LogService.instance.info('[Google视频] 🔄 生成进度: ${data['metadata']?['progress'] ?? 'unknown'} (尝试 ${i + 1}/$maxAttempts)');
        }
      } catch (e, s) {
        LogService.instance.error('[Google视频] ❌ 轮询过程中发生错误', e, s);
      }
    }
    
    throw Exception('视频生成超时');
  }

  /// 下载并保存视频
  Future<String?> _downloadAndSaveVideo(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[Google视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        LogService.instance.error('[Google视频] ❌ 下载视频失败 (状态码： ${response.statusCode})');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Google视频] ❌ 下载视频时出错', e, s);
      return null;
    }
  }

  /// 解析分辨率字符串为宽高
  Map<String, int> _parseDimensions(String resolution) {
    switch (resolution.toLowerCase()) {
      case '360p':
        return {'width': 640, 'height': 360};
      case '480p':
        return {'width': 854, 'height': 480};
      case '720p':
        return {'width': 1280, 'height': 720};
      case '1080p':
        return {'width': 1920, 'height': 1080};
      default:
        return {'width': 1280, 'height': 720}; // 默认720p
    }
  }
}
