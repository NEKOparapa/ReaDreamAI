// lib/services/video_service/platforms/bailian_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../base/log/log_service.dart';
import '../../../models/api_model.dart';
import '../video_platform.dart';

/// 阿里百炼 (通义万相) 视频平台的具体实现。
class BailianPlatform implements VideoPlatform {
  final http.Client client;

  BailianPlatform({required this.client});

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
    // 检查是否存在参考图路径，并决定调用哪个方法
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 如果有参考图，调用"文+图生视频"方法
      return await _generateWithImage(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        apiConfig: apiConfig,
        referenceImagePath: referenceImagePath,
      );
    } else {
      // 如果没有参考图，调用"文生视频"方法
      return await _generateWithTextOnly(
        positivePrompt: positivePrompt,
        saveDir: saveDir,
        apiConfig: apiConfig,
      );
    }
  }

  /// 文生视频方法
  Future<List<String>?> _generateWithTextOnly({
    required String positivePrompt,
    required String saveDir,
    required ApiModel apiConfig,
  }) {
    LogService.instance.info('[百炼视频] 🚀 启动文生视频任务...');
    // 构造请求的 input 部分 - 文生视频只需要 prompt
    final Map<String, dynamic> input = {
      "prompt": positivePrompt,
    };
    // 调用共用方法提交任务，isTextToVideo 标记为 true
    return _submitTaskAndPoll(
      input: input, 
      apiConfig: apiConfig, 
      saveDir: saveDir,
      isTextToVideo: true,
    );
  }

  /// 文+图生视频方法
  Future<List<String>?> _generateWithImage({
    required String positivePrompt,
    required String saveDir,
    required ApiModel apiConfig,
    required String referenceImagePath,
  }) async {
    LogService.instance.info('[百炼视频] 🚀 检测到参考图，启动图生视频任务...');
    
    // 处理参考图，将其转换为 Base64 编码的 URL
    final imageUrl = await _imageToBase64(referenceImagePath);
    if (imageUrl == null) {
      // 如果转换失败，抛出错误而不是退化为文生视频
      throw Exception('参考图处理失败，无法进行图生视频任务');
    }
    
    // 构造请求的 input 部分 - 图生视频需要 prompt 和 img_url
    final Map<String, dynamic> input = {
      "prompt": positivePrompt,
      "img_url": imageUrl,
    };
    
    LogService.instance.info('[百炼视频] ✅ 已将图片转换为 Base64 并添加到请求中。');
    
    // 调用共用方法提交任务，isTextToVideo 标记为 false
    return _submitTaskAndPoll(
      input: input, 
      apiConfig: apiConfig, 
      saveDir: saveDir,
      isTextToVideo: false,
    );
  }

  // =======================================================================
  // 共用方法
  // ======================================================================

  /// 提交任务并轮询结果
  Future<List<String>?> _submitTaskAndPoll({
    required Map<String, dynamic> input,
    required ApiModel apiConfig,
    required String saveDir,
    required bool isTextToVideo,
  }) async {
    // 根据任务类型自动修正模型名称
    final correctedModel = _getCorrectModelName(apiConfig.model, isTextToVideo);
    LogService.instance.info('[百炼视频] 自动修正模型为: $correctedModel (任务类型: ${isTextToVideo ? "文生视频" : "图生视频"})');
    
    // 构造完整的请求体 (payload)
    final payload = {
      "model": correctedModel, 
      "input": input,
      "parameters": {
        "prompt_extend": false, // 关闭提示词扩展
      }
    };

    // 定义 API 端点和请求头
    final endpoint = Uri.parse('${apiConfig.url}/services/aigc/video-generation/video-synthesis');
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${apiConfig.apiKey}",
      "X-DashScope-Async": "enable", // 启用异步模式
    };

    try {
      // 记录请求信息用于调试
      LogService.instance.info('[百炼视频] 📤 发送请求到: $endpoint');
      // LogService.instance.info('[百炼视频] 📋 请求体: ${jsonEncode(payload)}');
      
      // 发送 POST 请求提交任务
      final initialResponse = await client.post(
        endpoint,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      // 检查响应状态码
      if (initialResponse.statusCode != 200) {
        throw Exception('百炼视频 API 任务提交失败 (${initialResponse.statusCode}): ${initialResponse.body}');
      }

      // 解析响应，获取任务 ID
      final responseData = jsonDecode(utf8.decode(initialResponse.bodyBytes));
      final taskId = responseData['output']?['task_id'];

      if (taskId == null) {
        throw Exception('百炼视频 API 未返回 task_id。响应: ${jsonEncode(responseData)}');
      }
      LogService.instance.info('[百炼视频] ✅ 任务提交成功，Task ID: $taskId。开始轮询任务状态...');

      // 使用任务 ID 开始轮询任务状态
      return await _pollTaskStatus(taskId, saveDir, apiConfig);

    } catch (e, s) {
      LogService.instance.error('[百炼视频] ❌ 提交任务时发生严重错误', e, s);
      rethrow; // 重新抛出异常
    }
  }

  /// 根据任务类型自动转换和修正模型名称。
  String _getCorrectModelName(String originalModel, bool isTextToVideo) {
    if (isTextToVideo) {
      // 如果是文生视频，确保模型名是 t2v
      return originalModel.replaceAll('i2v', 't2v');
    } else {
      // 如果是图生视频，确保模型名是 i2v
      return originalModel.replaceAll('t2v', 'i2v');
    }
  }

  /// 轮询任务状态
  Future<List<String>?> _pollTaskStatus(String taskId, String saveDir, ApiModel apiConfig) async {
    final taskEndpoint = Uri.parse('${apiConfig.url}/tasks/$taskId');
    final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

    const maxAttempts = 30; // 最大轮询次数 (30 * 15s ≈ 7.5 分钟)
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 15)); // 根据官方文档建议，轮询间隔15秒

      try {
        final response = await client.get(taskEndpoint, headers: headers);
        if (response.statusCode != 200) {
          LogService.instance.warn('[百炼视频] ⚠️ 轮询任务状态失败 (状态码: ${response.statusCode})，继续尝试...');
          continue;
        }

        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final status = data['output']?['task_status'];

        LogService.instance.info('[百炼视频] 🔄 任务状态: $status (尝试 ${i + 1}/$maxAttempts)');

        if (status == 'SUCCEEDED') {
          final videoUrl = data['output']?['video_url'];
          if (videoUrl == null) {
            throw Exception('任务成功但未找到视频URL。响应： ${jsonEncode(data)}');
          }
          LogService.instance.success('[百炼视频] ✅ 任务成功！视频URL: $videoUrl');
          final filePath = await _downloadAndSaveVideo(videoUrl, saveDir);
          return filePath != null ? [filePath] : null;

        } else if (status == 'FAILED') {
          // 获取详细的错误信息
          final errorMessage = data['output']?['message'] ?? '未知错误';
          throw Exception('任务处理失败。原因: $errorMessage');
        }
        // 如果是 PENDING 或 RUNNING，则继续轮询
      } catch (e, s) {
        LogService.instance.error('[百炼视频] ❌ 轮询过程中发生错误', e, s);
        // 如果是任务失败的异常，直接抛出
        if (e.toString().contains('任务处理失败')) {
          rethrow;
        }
        // 其他错误继续轮询
      }
    }
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
        LogService.instance.success('[百炼视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        LogService.instance.error('[百炼视频] ❌ 下载视频失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[百炼视频] ❌ 下载视频时出错', e, s);
      return null;
    }
  }

  /// 将图片文件转为 Base64 data URL
  Future<String?> _imageToBase64(String imagePath) async {
    if (imagePath.startsWith('http')) return imagePath; // 如果是网络 URL，直接返回

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        LogService.instance.warn('[百炼视频] ⚠️ 本地参考图文件不存在: $imagePath');
        return null;
      }
      
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final extension = p.extension(imagePath).replaceFirst('.', '').toLowerCase();
      final mimeType = _getMimeTypeFromExtension(extension);
      
      return 'data:$mimeType;base64,$base64String';
    } catch (e, s) {
      LogService.instance.error('[百炼视频] ❌ 读取本地参考图并转为Base64时出错', e, s);
      return null;
    }
  }

  /// 根据文件扩展名获取 MIME 类型
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
}