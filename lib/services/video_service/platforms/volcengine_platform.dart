// lib/services/video_service/platforms/volcengine_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../base/log/log_service.dart';
import '../../../base/api_model.dart';
import '../video_platform.dart';

/// 火山方舟视频平台的具体实现。
class VolcenginePlatform implements VideoPlatform {
  final http.Client client;

  VolcenginePlatform({required this.client});

  /// 主入口方法，根据有无参考图，分发到不同的处理流程
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
      // 如果有参考图，调用“文+图生视频”方法
      return await _generateWithImage(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        apiConfig: apiConfig,
        resolution: resolution,
        duration: duration,
        referenceImagePath: referenceImagePath
      );
    } else {
      // 如果没有参考图，调用“文生视频”方法
      return await _generateWithTextOnly(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        apiConfig: apiConfig,
        resolution: resolution,
        duration: duration,
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
  }) {
    LogService.instance.info('[火山视频] 🚀 启动文生视频任务...');
    // 将分辨率和时长作为参数拼接到提示词中
    final promptWithParams = '$positivePrompt resolution:${resolution.toLowerCase()} duration:$duration';
    // 构造 content 列表
    final List<Map<String, dynamic>> content = [
      {"type": "text", "text": promptWithParams}
    ];

    return _submitTaskAndPoll(content: content, apiConfig: apiConfig, saveDir: saveDir);
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
    LogService.instance.info('[火山视频] 🚀 检测到参考图，启动文+图生视频任务...');
    // 构造 content 列表，首先添加文本部分
    final promptWithParams = '$positivePrompt resolution:${resolution.toLowerCase()} duration:$duration';
    final List<Map<String, dynamic>> content = [
      {"type": "text", "text": promptWithParams}
    ];

    try {
      String imageUrl;
      if (referenceImagePath.toLowerCase().startsWith('http')) {
        imageUrl = referenceImagePath;
        LogService.instance.info('[火山视频] ℹ️ 使用网络图片URL: $referenceImagePath');
      } else {
        LogService.instance.info('[火山视频] ℹ️ 检测到本地图片路径，正在进行Base64编码...');
        imageUrl = await _encodeImageToBase64DataUri(referenceImagePath);
        LogService.instance.success('[火山视频] ✅ 本地图片编码成功');
      }
      // 将处理好的图片 URL 添加到 content 列表
      content.add({
        "type": "image_url",
        "image_url": {"url": imageUrl}
      });
    } catch (e, s) {
      LogService.instance.error('[火山视频] ❌ 处理本地参考图时发生错误', e, s);
      throw Exception('处理本地参考图失败: $e');
    }
    
    return _submitTaskAndPoll(content: content, apiConfig: apiConfig, saveDir: saveDir);
  }

  // =======================================================================
  // 共用方法
  // =======================================================================

  /// 提交任务并轮询结果
  Future<List<String>?> _submitTaskAndPoll({
    required List<Map<String, dynamic>> content,
    required ApiModel apiConfig,
    required String saveDir,
  }) async {
    final payload = {
      "model": apiConfig.model,
      "content": content,
    };
    final endpoint = Uri.parse('${apiConfig.url}/contents/generations/tasks');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}",
    };

    try {
      final initialResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (initialResponse.statusCode != 200 && initialResponse.statusCode != 201) {
        throw Exception('火山视频 API 任务提交失败 (${initialResponse.statusCode}): ${initialResponse.body}');
      }

      final responseData = jsonDecode(utf8.decode(initialResponse.bodyBytes));
      final taskId = responseData['id'];

      if (taskId == null) {
        throw Exception('火山视频 API 未返回 task_id。响应: ${jsonEncode(responseData)}');
      }
      LogService.instance.info('[火山视频] ✅ 任务提交成功，Task ID: $taskId。开始轮询任务状态...');

      return await _pollTaskStatus(taskId, saveDir, apiConfig);
    } catch (e, s) {
      LogService.instance.error('[火山视频] ❌ 提交任务时发生严重错误', e, s);
      rethrow;
    }
  }

  /// 轮询任务状态
  Future<List<String>?> _pollTaskStatus(String taskId, String saveDir, ApiModel apiConfig) async {
      final taskEndpoint = Uri.parse('${apiConfig.url}/contents/generations/tasks/$taskId');
      final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

      const maxAttempts = 15; // 最大轮询次数 (15 * 10s = 2.5分钟)
      for (int i = 0; i < maxAttempts; i++) {
        await Future.delayed(const Duration(seconds: 10)); // 轮询间隔10秒

        try {
          final response = await client.get(taskEndpoint, headers: headers).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            LogService.instance.warn('[火山视频] ⚠️ 轮询任务状态失败 (状态码: ${response.statusCode})，响应: ${response.body}，继续尝试...');
            continue;
          }

          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final status = data['status'];
          LogService.instance.info('[火山视频] 🔄 任务状态: $status (尝试 ${i + 1}/$maxAttempts)');

          if (status == 'succeeded') {
            final videoUrl = data['content']?['video_url'];
            if (videoUrl == null || (videoUrl is! String) || videoUrl.isEmpty) {
              throw Exception('任务成功但未找到有效的视频URL。响应: ${jsonEncode(data)}');
            }
            LogService.instance.success('[火山视频] ✅ 任务成功！视频URL: $videoUrl');
            final filePath = await _downloadAndSaveVideo(videoUrl, saveDir);
            return filePath != null ? [filePath] : null;

          } else if (status == 'failed') {
            final errorInfo = jsonEncode(data['error']);
            LogService.instance.error('[火山视频] ❌ 任务处理失败。原因: $errorInfo');
            throw Exception('任务处理失败。原因: $errorInfo');
          }
          // 如果状态是 queued 或 running，则继续循环等待
        } catch (e, s) {
          LogService.instance.error('[火山视频] ❌ 轮询过程中发生错误', e, s);
        }
      }
      LogService.instance.error('[火山视频] ❌ 任务超时，超过最大轮询次数 ($maxAttempts)。');
      throw Exception('任务超时，超过最大轮询次数。');
    }

  /// 下载并保存视频
  Future<String?> _downloadAndSaveVideo(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[火山视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        LogService.instance.error('[火山视频] ❌ 下载视频失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[火山视频] ❌ 下载视频时出错', e, s);
      return null;
    }
  }

  /// 辅助方法：将本地图片文件编码为 Base64 Data URI
  Future<String> _encodeImageToBase64DataUri(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException("参考图文件不存在", filePath);
    }
    final imageBytes = await file.readAsBytes();
    String format = p.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (format == 'jpg') format = 'jpeg';
    
    const supportedFormats = {'jpeg', 'png', 'webp', 'bmp', 'tiff', 'gif'};
    if (!supportedFormats.contains(format)) {
        throw Exception('不支持的图片格式: $format');
    }

    final base64String = base64Encode(imageBytes);
    return 'data:image/$format;base64,$base64String';
  }
}