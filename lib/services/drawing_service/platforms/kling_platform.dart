// lib/services/drawing_service/platforms/kling_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// Kling 平台的具体实现。
class KlingPlatform implements DrawingPlatform {
  final http.Client client;
  final ApiModel apiConfig;

  static const String _baseUrl = 'https://api-beijing.klingai.com';

  KlingPlatform({required this.client, required this.apiConfig});

  /// 根据传入的参数决定执行文生图还是图生图。
  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    String? referenceImagePath,
  }) async {
    // 如果提供了参考图路径，则执行图生图流程
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      print('[Kling] 🚀 正在请求 图生图...');
      return _generateImageToImage(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
        referenceImagePath: referenceImagePath,
      );
    } else {
      // 否则，执行文生图流程
      print('[Kling] 🚀 正在请求 文生图...');
      return _generateTextToImage(
        positivePrompt: positivePrompt,
        negativePrompt: negativePrompt,
        saveDir: saveDir,
        count: count,
        width: width,
        height: height,
      );
    }
  }

  //----------------------------------------------------------------------------
  // 私有方法：文生图 (Text-to-Image)
  //----------------------------------------------------------------------------

  /// 执行文生图的具体逻辑。
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
  }) async {
    final payload = {
      'prompt': positivePrompt,
      'negative_prompt': negativePrompt,
      'n': count,
      'model_name': apiConfig.model.isNotEmpty ? apiConfig.model : 'kling-v2',
      'aspect_ratio': _mapToAspectRatio(width, height),
    };

    final taskId = await _createGenerationTask(payload);
    if (taskId == null) return null;

    return _executeGenerationFlow(taskId, saveDir);
  }

  //----------------------------------------------------------------------------
  // 私有方法：图生图 (Image-to-Image)
  //----------------------------------------------------------------------------

  /// 执行图生图的具体逻辑。
  Future<List<String>?> _generateImageToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required String referenceImagePath,
  }) async {
    String imageValue;
    // 判断参考图是云端URL还是本地路径
    if (referenceImagePath.startsWith('http://') || referenceImagePath.startsWith('https://')) {
      imageValue = referenceImagePath;
      print('[Kling] ℹ️ 使用云端参考图: $imageValue');
    } else {
      final imageFile = File(referenceImagePath);
      if (!await imageFile.exists()) {
        print('[Kling] ❌ 参考图片文件不存在: $referenceImagePath');
        return null;
      }
      final imageBytes = await imageFile.readAsBytes();
      imageValue = base64Encode(imageBytes);
      print('[Kling] ℹ️ 已加载并编码本地参考图: $referenceImagePath');
    }

    final payload = {
      'prompt': positivePrompt,
      'negative_prompt': negativePrompt,
      'n': count,
      'model_name': apiConfig.model,
      'aspect_ratio': _mapToAspectRatio(width, height),
      'image': imageValue,
    };

    final taskId = await _createGenerationTask(payload);
    if (taskId == null) return null;

    return _executeGenerationFlow(taskId, saveDir);
  }

  //----------------------------------------------------------------------------
  // 私有辅助方法 (通用)
  //----------------------------------------------------------------------------

  /// 执行通用的生成流程：创建任务 -> 轮询状态 -> 下载结果。
  Future<List<String>?> _executeGenerationFlow(String taskId, String saveDir) async {
    print('[Kling] ✅ 任务创建成功，ID: $taskId');

    // 轮询任务状态，直到任务完成或失败。
    final resultData = await _pollTaskStatus(taskId);
    if (resultData == null) return null;
    print('[Kling] ✅ 任务状态轮询完成，结果: ${resultData['task_status']}');

    // 检查任务是否成功。
    final imagesInfo = (resultData['task_result'] as Map?)?['images'] as List?;
    if (imagesInfo == null || imagesInfo.isEmpty) {
      print('[Kling] ❓ 任务已成功，但 API 未返回图像信息。');
      return null;
    }

    // 为每个图像信息创建下载任务。
    final downloadFutures = imagesInfo.map((imgInfo) {
      final imageUrl = (imgInfo as Map)['url'] as String?;
      return imageUrl != null ? _downloadImage(imageUrl, saveDir) : Future.value(null);
    });

    // 并行等待所有下载任务完成，并过滤掉失败的结果(null)。
    final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();

    // 返回下载成功的图像路径列表。
    return imagePaths.isNotEmpty ? imagePaths : null;
  }

  /// 向 Kling API 提交请求以创建图像生成任务。
  Future<String?> _createGenerationTask(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$_baseUrl/v1/images/generations');
    final headers = {
      'Authorization': 'Bearer ${_generateAuthToken()}',
      'Content-Type': 'application/json'
    };

    try {
      final response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['code'] == 0) {
        final taskId = data['data']['task_id'] as String;
        return taskId;
      }

      print('[Kling] ❌ 创建任务失败: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      print('[Kling] ❌ 创建任务时发生网络或超时错误: $e');
      return null;
    }
  }

  /// 轮询任务状态，直到任务完成、失败或超时。
  Future<Map<String, dynamic>?> _pollTaskStatus(String taskId) async {
    const maxRetries = 60;
    const waitInterval = Duration(seconds: 5);

    for (var i = 0; i < maxRetries; i++) {
      await Future.delayed(waitInterval);

      final uri = Uri.parse('$_baseUrl/v1/images/generations/$taskId');
      final headers = {'Authorization': 'Bearer ${_generateAuthToken()}'};

      try {
        final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (response.statusCode == 200 && data['code'] == 0) {
          final status = data['data']['task_status'] as String;
          print('[Kling]  polled status: $status');
          if (status == 'succeed') {
            return data['data'];
          }
          if (status == 'failed') {
            print('[Kling] ❌ 任务失败: ${data['data']['task_status_msg']}');
            return null;
          }
        } else {
          print('[Kling] ⚠️ 轮询请求失败或返回错误: ${response.statusCode} ${response.body}');
        }
      } catch (e) {
        print('[Kling] ❌ 轮询期间发生网络或解析错误: $e');
      }
    }
    print('[Kling] ❌ 轮询超时。');
    return null;
  }

  /// 从给定的 URL 下载图片并保存到本地。
  Future<String?> _downloadImage(String url, String saveDir) async {
    try {
      print('[Kling] 📥 正在下载图片: $url');
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        final extension = p.extension(Uri.parse(url).path).isNotEmpty
            ? p.extension(Uri.parse(url).path)
            : '.png';
        final imagePath = p.join(saveDir, '${const Uuid().v4()}$extension');
        await Directory(saveDir).create(recursive: true);
        await File(imagePath).writeAsBytes(response.bodyBytes);
        print('[Kling] ✅ 图片已保存到: $imagePath');
        return imagePath;
      }
      print('[Kling] ❌ 从 $url 下载图片失败。状态码: ${response.statusCode}');
      return null;
    } catch (e) {
      print('[Kling] ❌ 从 $url 下载图片时出错: $e');
      return null;
    }
  }

  /// 生成用于身份验证的 JWT (JSON Web Token)。
  String _generateAuthToken() {
    final accessKey = apiConfig.accessKey;
    final secretKey = apiConfig.secretKey;

    if (accessKey == null || accessKey.isEmpty) {
      throw Exception('Kling 平台需要有效的 Access Key');
    }
    if (secretKey == null || secretKey.isEmpty) {
      throw Exception('Kling 平台需要有效的 Secret Key');
    }

    final header = {'alg': 'HS256'};
    final payload = {
      'iss': accessKey,
      'exp': DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
      'nbf': DateTime.now().subtract(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000,
    };

    final jwt = JWT(payload, header: header);
    final token = jwt.sign(SecretKey(secretKey), algorithm: JWTAlgorithm.HS256, noIssueAt: true);

    return token;
  }

  /// 将宽高尺寸映射到 API 支持的宽高比字符串。
  String _mapToAspectRatio(int width, int height) {
    // 优先匹配精确尺寸
    if (width == 1280 && height == 720) return '16:9';
    if (width == 720 && height == 1280) return '9:16';
    if (width == 1024 && height == 1024) return '1:1';
    if (width == 1024 && height == 768) return '4:3';
    if (width == 768 && height == 1024) return '3:4';

    // 根据比例进行模糊匹配
    final ratio = width / height;
    if ((ratio - 16 / 9).abs() < 0.05) return '16:9';
    if ((ratio - 9 / 16).abs() < 0.05) return '9:16';
    if ((ratio - 1).abs() < 0.05) return '1:1';
    if ((ratio - 4 / 3).abs() < 0.05) return '4:3';
    if ((ratio - 3 / 4).abs() < 0.05) return '3:4';
    if ((ratio - 3 / 2).abs() < 0.05) return '3:2';
    if ((ratio - 2 / 3).abs() < 0.05) return '2:3';
    if ((ratio - 21 / 9).abs() < 0.05) return '21:9';

    // 默认返回一个常用比例
    return '16:9';
  }
}