// lib/services/video_service/platforms/google_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../base/log/log_service.dart';
import '../../../base/api_model.dart';
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
    LogService.instance.info('[Google视频] 🚀 启动视频生成任务...');
    
    final instance = <String, dynamic>{
      "prompt": positivePrompt,
    };

    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      LogService.instance.info('[Google视频] 检测到参考图，任务类型: 文+图生视频。');
      String imageData;
      String mimeType;

      if (referenceImagePath.toLowerCase().startsWith('http')) {
        final imageResponse = await client.get(Uri.parse(referenceImagePath));
        if (imageResponse.statusCode == 200) {
          imageData = base64Encode(imageResponse.bodyBytes);
          // 尝试从URL或响应头获取MIME类型，如果失败则根据URL路径猜测
          mimeType = imageResponse.headers['content-type'] ?? _getMimeType(referenceImagePath);
        } else {
          throw Exception('无法下载参考图片: $referenceImagePath');
        }
      } else {
        final file = File(referenceImagePath);
        if (!await file.exists()) {
          throw FileSystemException("参考图文件不存在", referenceImagePath);
        }
        imageData = base64Encode(await file.readAsBytes());
        mimeType = _getMimeType(referenceImagePath); // 根据文件路径获取MIME类型
      }

      // 关键修正：同时提供 bytesBase64Encoded 和 mimeType
      instance['image'] = {
        "bytesBase64Encoded": imageData,
        "mimeType": mimeType,
      };
    }

    final parameters = {
      "durationSeconds": 6,
      "aspectRatio": "16:9",
      "resolution": resolution,
    };
    
    final payload = {
      "instances": [instance],
      "parameters": parameters,
    };

    final endpoint = Uri.parse('${apiConfig.url}/models/${apiConfig.model}:predictLongRunning');
    
    try {
      final response = await client.post(
        endpoint,
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiConfig.apiKey,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return await _pollOperation(data['name'], saveDir, apiConfig);
      } else {
        // 捕获到400错误时，在这里抛出异常，堆栈信息会显示出来
        throw Exception('Google视频 API 请求失败 (${response.statusCode}): ${response.body}');
      }
    } catch (e, s) {
      LogService.instance.error('[Google视频] ❌ 生成视频时发生错误', e, s);
      rethrow;
    }
  }

  /// 轮询操作状态
  Future<List<String>?> _pollOperation(String operationName, String saveDir, ApiModel apiConfig) async {
    final endpoint = Uri.parse('${apiConfig.url}/$operationName');
    
    const maxAttempts = 30;
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 10));
      
      try {
        final response = await client.get(
          endpoint,
          headers: { "x-goog-api-key": apiConfig.apiKey },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['done'] == true) {
            // 打印完整的最终响应，用于调试
            LogService.instance.info('[Google视频] ✅ 操作完成，收到最终响应: ${response.body}');

            if (data.containsKey('error')) {
              throw Exception('视频生成任务已完成，但报告了错误: ${data['error']['message']}');
            }
            
            // 更健壮的、分步的解析逻辑
            final responseData = data['response'];
            if (responseData == null || responseData is! Map) {
              throw Exception('视频生成成功，但响应中缺少 "response" 字段或其格式不正确。');
            }

            final generateVideoData = responseData['generateVideoResponse'];
            if (generateVideoData == null || generateVideoData is! Map) {
              throw Exception('视频生成成功，但响应中缺少 "generateVideoResponse" 字段或其格式不正确。');
            }
            
            final samples = generateVideoData['generatedSamples'];
            if (samples == null || samples is! List || samples.isEmpty) {
              // 这种情况很可能是因为内容被安全策略过滤了
              throw Exception('视频生成成功，但 "generatedSamples" 列表为空或不存在。这很可能是因为生成的内容被安全策略过滤掉了。');
            }
            
            final videoData = samples[0]?['video'];
            if (videoData == null || videoData is! Map) {
              throw Exception('视频生成成功，但在第一个样本中找不到 "video" 对象。');
            }

            final videoUri = videoData['uri'];
            if (videoUri == null || videoUri is! String) {
              throw Exception('视频生成成功，但无法在 video 对象中找到 "uri" 字符串。');
            }
            
            // 只有当所有检查都通过时，才继续下载
            LogService.instance.success('[Google视频] ✅ 视频URI解析成功！');
            final filePath = await _downloadAndSaveVideo(videoUri, saveDir, apiConfig.apiKey);
            return filePath != null ? [filePath] : null;
          }
          
          LogService.instance.info('[Google视频] 🔄 视频生成中... (尝试 ${i + 1}/$maxAttempts)');
        } else {
            LogService.instance.warn('[Google视频] ⚠️ 轮询请求失败 (状态码: ${response.statusCode}): ${response.body}');
        }
      } catch (e, s) {
        // 将捕获到的异常重新抛出，同时记录，避免丢失原始错误信息
        LogService.instance.error('[Google视频] ❌ 轮询过程中发生错误', e, s);
        rethrow;
      }
    }
    
    throw Exception('视频生成超时');
  }

  /// 下载并保存视频
  Future<String?> _downloadAndSaveVideo(String url, String saveDir, String apiKey) async {
    try {
      final response = await client.get(
        Uri.parse(url),
        headers: { "x-goog-api-key": apiKey },
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        return videoPath;
      } else {
        LogService.instance.error('[Google视频] ❌ 下载视频失败 (状态码： ${response.statusCode}) Body: ${response.body}');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Google视频] ❌ 下载视频时出错', e, s);
      return null;
    }
  }

  // 根据文件路径或URL获取MIME类型的辅助方法
  String _getMimeType(String path) {
    final extension = p.extension(path).toLowerCase();
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      // 可以根据需要添加更多支持的格式
      default:
        // 提供一个合理的默认值
        return 'image/png';
    }
  }
}