// lib/services/drawing_service/platforms/fal_platform.dart

import 'dart:io';
import 'package:fal_client/fal_client.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../base/api_model.dart';
import '../../../base/log/log_service.dart';
import '../drawing_platform.dart';

/// Fal.ai 平台的具体实现。
class FalPlatform implements DrawingPlatform {
  FalPlatform();

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
    LogService.instance.info('[Fal.ai] 🚀 正在执行绘图任务...');

    // 使用从 apiConfig 中获取的 key 初始化 Fal 客户端
    final fal = FalClient.withCredentials(apiConfig.apiKey);

    try {
      final input = <String, dynamic>{
        "prompt": positivePrompt,
        "num_images": count,
        "image_size": _mapImageSize(width, height),
      };

      // TODO: 实现图生图逻辑
      // Fal 的图生图需要先上传图片获取 URL，然后将 URL 作为参数
      // if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      //   final tempDir = await getTemporaryDirectory();
      //   final file = XFile(referenceImagePath);
      //   final imageUrl = await fal.storage.upload(file,
      //     destination: tempDir.path,
      //   );
      //   input['image_url'] = imageUrl;
      //   LogService.instance.info('[Fal.ai] 已上传参考图: $imageUrl');
      // }

      LogService.instance.info('[Fal.ai] 发送请求到模型: ${apiConfig.model} with input: $input');
      
      // 使用 fal.run 直接调用并等待结果
      final result = await fal.run(apiConfig.model, input: input)
          .timeout(const Duration(seconds: 180));

      // 检查返回结果中是否有 images 字段
      if (result.data['images'] == null || (result.data['images'] as List).isEmpty) {
        LogService.instance.error('[Fal.ai] ❌ API 未返回图像数据。响应: ${result.data}');
        return null;
      }
      
      final imageUrls = (result.data['images'] as List)
          .map((image) => image['url'] as String)
          .toList();

      LogService.instance.info('[Fal.ai] 成功获取 ${imageUrls.length} 张图片的 URL，准备下载...');
      
      // 并行下载所有图片
      final downloadFutures = imageUrls.map((url) => _downloadAndSaveImage(url, saveDir));
      final savedImagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();

      return savedImagePaths.isNotEmpty ? savedImagePaths : null;

    } catch (e, s) {
      LogService.instance.error('[Fal.ai] ❌ 请求或处理 Fal API 时发生严重错误', e, s);
      return null;
    }
  }

  /// 将 Fal API 返回的图片 URL 下载并保存到本地
  Future<String?> _downloadAndSaveImage(String url, String saveDir) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
        await Directory(saveDir).create(recursive: true);
        await File(imagePath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[Fal.ai] 图片已保存到: $imagePath');
        return imagePath;
      } else {
        LogService.instance.warn('[Fal.ai] ⚠️ 下载图片失败 (状态码: ${response.statusCode}) from URL: $url');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[Fal.ai] ❌ 下载图片时出错', e, s);
      return null;
    }
  }

  /// 将宽高映射为 Fal API 支持的 image_size 字符串
  String _mapImageSize(int width, int height) {
    if (width == height) return "square";
    
    double aspectRatio = width / height;
    if (aspectRatio > 1) { // 横向
      if ((aspectRatio - 16/9).abs() < 0.1) return "landscape_16_9";
      if ((aspectRatio - 4/3).abs() < 0.1) return "landscape_4_3";
      return "landscape";
    } else { // 纵向
      if ((aspectRatio - 9/16).abs() < 0.1) return "portrait_16_9";
      if ((aspectRatio - 3/4).abs() < 0.1) return "portrait_4_3";
      return "portrait";
    }
  }
}