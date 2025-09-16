// lib/services/video_service/platforms/bailian_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../models/api_model.dart';
import '../video_platform.dart';

/// 阿里百炼 (通义万相) 视频平台的具体实现。
class BailianPlatform implements VideoPlatform {
  final http.Client client;

  BailianPlatform({required this.client});

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
    final Map<String, dynamic> input = {"prompt": positivePrompt};


    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      print('[百炼视频] 🚀 检测到参考图，启动图生视频任务...');
      final imageUrl = await _imageToBase64(referenceImagePath);
      if (imageUrl != null) {
        input['img_url'] = imageUrl;
        print('[百炼视频] ✅ 已将本地图片转换为 Base64 并添加到请求中。');
      } else {
        print('[百炼视频] ⚠️ 参考图处理失败，将作为纯文生视频任务执行。');
      }
    } else {
      print('[百炼视频] 🚀 启动文生视频任务...');
    }

    final payload = {
      "model": apiConfig.model, // 直接使用用户配置的模型
      "input": input,  // 包含 prompt 和可选的 img_url
      "parameters": {
        //"resolution": resolution,
        //"duration": duration, 
        "prompt_extend": false, // 关闭提示词扩展
      }
    };

    final endpoint = Uri.parse('${apiConfig.url}/services/aigc/video-generation/video-synthesis');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}",
      "X-DashScope-Async": "enable", // 启用异步模式
    };

    try {
      final initialResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (initialResponse.statusCode != 200) {
        throw Exception('百炼视频 API 任务提交失败 (${initialResponse.statusCode}): ${initialResponse.body}');
      }

      final responseData = jsonDecode(utf8.decode(initialResponse.bodyBytes));
      final taskId = responseData['output']?['task_id'];

      if (taskId == null) {
        throw Exception('百炼视频 API 未返回 task_id。响应: ${jsonEncode(responseData)}');
      }
      print('[百炼视频] ✅ 任务提交成功，Task ID: $taskId。开始轮询任务状态...');

      return await _pollTaskStatus(taskId, saveDir, apiConfig);

    } catch (e) {
      print('[百炼视频] ❌ 请求或处理百炼视频API时发生严重错误: $e');
      rethrow;
    }
  }


  Future<List<String>?> _pollTaskStatus(String taskId, String saveDir, ApiModel apiConfig) async {
    final taskEndpoint = Uri.parse('${apiConfig.url}/tasks/$taskId');
    final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

    const maxAttempts = 30; // 最大轮询次数 (例如 30 * 10s = 5 分钟)
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 15)); // 根据文档建议，轮询间隔15秒

      try {
        final response = await client.get(taskEndpoint, headers: headers);
        if (response.statusCode != 200) {
          print('[百炼视频] ⚠️ 轮询任务状态失败 (状态码: ${response.statusCode})，继续尝试...');
          continue;
        }

        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final status = data['output']?['task_status'];

        print('[百炼视频] 🔄 任务状态: $status (尝试 ${i + 1}/$maxAttempts)');

        if (status == 'SUCCEEDED') {
          final videoUrl = data['output']?['video_url'];
          if (videoUrl == null) {
            throw Exception('任务成功但未找到视频URL。响应: ${jsonEncode(data)}');
          }
          print('[百炼视频] ✅ 任务成功！视频URL: $videoUrl');
          final filePath = await _downloadAndSaveVideo(videoUrl, saveDir);
          return filePath != null ? [filePath] : null;

        } else if (status == 'FAILED') {
          throw Exception('任务处理失败。原因: ${jsonEncode(data['output']?['message'])}');
        }
        // 如果是 PENDING 或 RUNNING，继续轮询
      } catch (e) {
        print('[百炼视频] ❌ 轮询过程中发生错误: $e');
        // 即使轮询出错也继续尝试，直到超时
      }
    }
    throw Exception('任务超时，超过最大轮询次数。');
  }


  // 将图片文件转为 Base64 data URL
  Future<String?> _imageToBase64(String imagePath) async {
    // 如果已经是网络 URL，直接返回
    if (imagePath.startsWith('http')) return imagePath;

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print('[百炼视频] ⚠️ 本地参考图文件不存在: $imagePath');
        return null;
      }
      
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      
      // 根据文件扩展名确定 MIME 类型
      final extension = imagePath.split('.').last.toLowerCase();
      final mimeType = _getMimeTypeFromExtension(extension);
      
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      print('[百炼视频] ❌ 读取本地参考图并转为Base64时出错: $e');
      return null;
    }
  }

  // 根据文件扩展名返回对应的 MIME 类型
  String _getMimeTypeFromExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png'; // 未知类型的默认值
    }
  }

  Future<String?> _downloadAndSaveVideo(String url, String saveDir) async {
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        print('[百炼视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        print('[百炼视频] ❌ 下载视频失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e) {
      print('[百炼视频] ❌ 下载视频时出错: $e');
      return null;
    }
  }
}