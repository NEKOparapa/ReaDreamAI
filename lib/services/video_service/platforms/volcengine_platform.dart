// lib/services/video_service/platforms/volcengine_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../video_platform.dart';

/// 火山方舟视频平台的具体实现。
class VolcenginePlatform implements VideoPlatform {
  final http.Client client;

  VolcenginePlatform({required this.client});

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
    final List<Map<String, dynamic>> content = [];

    // 添加文本提示词，并将分辨率和时长作为参数拼接到提示词中
    final promptWithParams = '$positivePrompt resolution:${resolution.toLowerCase()} duration:$duration';
    content.add({"type": "text", "text": promptWithParams});


    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      print('[火山视频] 🚀 检测到参考图，启动文+图生视频任务...');
      String imageUrl;
      if (referenceImagePath.toLowerCase().startsWith('http')) {
        // 如果是URL，直接使用
        print('[火山视频] ℹ️ 使用网络图片URL: $referenceImagePath');
        imageUrl = referenceImagePath;
      } else {
        // 如果是本地路径，进行Base64编码
        print('[火山视频] ℹ️ 检测到本地图片路径，正在进行Base64编码...');
        try {
          imageUrl = await _encodeImageToBase64DataUri(referenceImagePath);
          print('[火山视频] ✅ 本地图片编码成功');
        } catch (e) {
          print('[火山视频] ❌ 处理本地参考图时发生错误: $e');
          // 抛出异常，中断任务
          throw Exception('处理本地参考图失败: $e');
        }
      }
      content.add({
        "type": "image_url",
        "image_url": {"url": imageUrl}
      });
    } else {
      print('[火山视频] 🚀 启动文生视频任务...');
    }
   

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
      print('[火山视频] ✅ 任务提交成功，Task ID: $taskId。开始轮询任务状态...');

      return await _pollTaskStatus(taskId, saveDir, apiConfig);
    } catch (e) {
      print('[火山视频] ❌ 请求或处理火山视频API时发生严重错误: $e');
      rethrow;
    }
  }

  /// 将本地图片文件编码为 Base64 Data URI
  Future<String> _encodeImageToBase64DataUri(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException("参考图文件不存在", filePath);
    }

    final imageBytes = await file.readAsBytes();
    
    // 从文件扩展名获取图片格式
    String format = p.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (format == 'jpg') {
        format = 'jpeg'; // API规范中常见jpeg
    }
    // 根据文档，支持 jpeg, png, webp, bmp, tiff, gif
    const supportedFormats = {'jpeg', 'png', 'webp', 'bmp', 'tiff', 'gif'};
    if (!supportedFormats.contains(format)) {
        throw Exception('不支持的图片格式: $format');
    }

    final base64String = base64Encode(imageBytes);

    return 'data:image/$format;base64,$base64String';
  }

  Future<List<String>?> _pollTaskStatus(String taskId, String saveDir, ApiModel apiConfig) async {
      final taskEndpoint = Uri.parse('${apiConfig.url}/contents/generations/tasks/$taskId');
      
      final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

      const maxAttempts = 15; 
      for (int i = 0; i < maxAttempts; i++) {
        // 建议将轮询间隔设置得长一些，例如10-15秒，以避免过于频繁的请求
        await Future.delayed(const Duration(seconds: 10));

        try {
          final response = await client.get(taskEndpoint, headers: headers).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            print('[火山视频] ⚠️ 轮询任务状态失败 (状态码: ${response.statusCode})，响应: ${response.body}，继续尝试...');
            continue;
          }

          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final status = data['status'];

          print('[火山视频] 🔄 任务状态: $status (尝试 ${i + 1}/$maxAttempts)');

          if (status == 'succeeded') {
            // 修正点2：根据文档，直接从 content 对象中获取 video_url 字符串
            final videoUrl = data['content']?['video_url'];

            if (videoUrl == null || (videoUrl is! String) || videoUrl.isEmpty) {
              throw Exception('任务成功但未找到有效的视频URL。响应: ${jsonEncode(data)}');
            }

            print('[火山视频] ✅ 任务成功！视频URL: $videoUrl');
            final filePath = await _downloadAndSaveVideo(videoUrl, saveDir);
            return filePath != null ? [filePath] : null;

          } else if (status == 'failed') {
            // 任务失败，记录错误信息并抛出异常
            final errorInfo = jsonEncode(data['error']);
            print('[火山视频] ❌ 任务处理失败。原因: $errorInfo');
            throw Exception('任务处理失败。原因: $errorInfo');
          }
          // 如果状态是 queued 或 running，则继续循环等待
        } catch (e) {
          // 捕获请求超时、解析错误等异常
          print('[火山视频] ❌ 轮询过程中发生错误: $e');
          // 如果是已知的不应重试的错误，可以 break 或 rethrow
        }
      }
      // 循环结束仍未成功，则视为超时
      print('[火山视频] ❌ 任务超时，超过最大轮询次数 ($maxAttempts)。');
      throw Exception('任务超时，超过最大轮询次数。');
    }


  Future<String?> _downloadAndSaveVideo(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        print('[火山视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        print('[火山视频] ❌ 下载视频失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e) {
      print('[火山视频] ❌ 下载视频时出错: $e');
      return null;
    }
  }
}