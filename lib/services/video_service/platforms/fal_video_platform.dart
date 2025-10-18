// lib/services/video_service/platforms/fal_video_platform.dart

import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:fal_client/fal_client.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../base/api_model.dart';
import '../../../base/log/log_service.dart';
import '../video_platform.dart';

/// Fal.ai 视频平台的具体实现。
class FalVideoPlatform implements VideoPlatform {
  FalVideoPlatform();

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String saveDir,
    required int count, // Fal 视频模型通常一次只生成一个
    required String resolution, // Fal 视频模型通常有固定分辨率，此参数可能不直接使用
    required int duration, // Fal 视频模型通常有固定时长，此参数可能不直接使用
    String? referenceImagePath,
    required ApiModel apiConfig,
  }) async {
    LogService.instance.info('[Fal.ai 视频] 🚀 正在执行视频生成任务...');
    final fal = FalClient.withCredentials(apiConfig.apiKey);

    try {
      final input = <String, dynamic>{
        "prompt": positivePrompt,
      };

      // 处理图生视频
      if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
        LogService.instance.info('[Fal.ai 视频] 检测到参考图，正在上传...');
        final file = XFile(referenceImagePath);
        // 使用 fal_client 上传文件并获取 URL
        final imageUrl = await fal.storage.upload(file);
        input['image_url'] = imageUrl;
        LogService.instance.success('[Fal.ai 视频] ✅ 参考图上传成功: $imageUrl');
      } else {
        LogService.instance.info('[Fal.ai 视频] ℹ️ 未提供参考图，执行文生视频任务。');
      }

      LogService.instance.info('[Fal.ai 视频] 发送请求到模型: ${apiConfig.model} with input: $input');
      
      // 直接调用并等待结果，视频生成可能耗时较长，设置较长的超时时间
      final result = await fal.run(apiConfig.model, input: input)
          .timeout(const Duration(minutes: 5));

      // Fal 的 SVD 模型返回结果中，视频 URL 在 video.url
      final videoData = result.data['video'];
      if (videoData == null || videoData['url'] == null) {
        LogService.instance.error('[Fal.ai 视频] ❌ API 未返回视频数据。响应: ${result.data}');
        return null;
      }
      
      final videoUrl = videoData['url'] as String;

      LogService.instance.info('[Fal.ai 视频] ✅ 成功获取视频 URL，准备下载...');
      
      final savedVideoPath = await _downloadAndSaveVideo(videoUrl, saveDir);
      return savedVideoPath != null ? [savedVideoPath] : null;

    } catch (e, s) {
      LogService.instance.error('[Fal.ai 视频] ❌ 请求或处理 Fal API 时发生严重错误', e, s);
      rethrow;
    }
  }

  /// 将 Fal API 返回的视频 URL 下载并保存到本地
  Future<String?> _downloadAndSaveVideo(String url, String saveDir) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
      if (response.statusCode == 200) {
        final videoPath = p.join(saveDir, '${const Uuid().v4()}.mp4');
        await Directory(saveDir).create(recursive: true);
        await File(videoPath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[Fal.ai 视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        LogService.instance.warn('[Fal.ai 视频] ⚠️ 下载视频失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Fal.ai 视频] ❌ 下载视频时出错', e, s);
      return null;
    }
  }
}