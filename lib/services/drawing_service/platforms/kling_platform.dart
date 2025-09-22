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
import '../../../base/log/log_service.dart';

/// Kling 平台的具体实现。
class KlingPlatform implements DrawingPlatform {
  // HTTP 客户端，用于发送网络请求
  final http.Client client;

  // Kling API 的基础 URL
  static const String _baseUrl = 'https://api-beijing.klingai.com';

  // 构造函数，需要传入一个 http.Client 实例
  KlingPlatform({required this.client});

  /// 根据传入的参数决定执行文生图还是图生图。
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
    // 如果提供了参考图路径，则执行图生图流程
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      LogService.instance.info('[Kling] 正在准备进行 图生图任务...');
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
    } else {
      // 否则，执行文生图流程
      LogService.instance.info('[Kling] 正在准备进行 文生图任务...');
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
    required ApiModel apiConfig,
  }) async {
    // 构建请求体 (payload)
    final payload = {
      'prompt': positivePrompt,
      'negative_prompt': negativePrompt,
      'n': count,
      'model_name': apiConfig.model.isNotEmpty ? apiConfig.model : 'kling-v2', // 模型名称
      'aspect_ratio': _mapToAspectRatio(width, height), // 宽高比
    };

    // 创建生成任务并获取任务ID
    final taskId = await _createGenerationTask(payload,apiConfig);
    if (taskId == null) return null; // 如果任务创建失败，则返回 null

    // 执行后续的生成流程（轮询状态、下载结果）
    return _executeGenerationFlow(taskId, saveDir,apiConfig);
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
    required ApiModel apiConfig,
    required String referenceImagePath,
  }) async {
    String imageValue;
    // 判断参考图是云端URL还是本地路径
    if (referenceImagePath.startsWith('http://') || referenceImagePath.startsWith('https://')) {
      imageValue = referenceImagePath;
      LogService.instance.info('[Kling] 使用云端参考图: $imageValue');
    } else {
      // 如果是本地路径，读取文件并进行 Base64 编码
      final imageFile = File(referenceImagePath);
      if (!await imageFile.exists()) {
        LogService.instance.error('[Kling] 参考图片文件不存在: $referenceImagePath');
        return null;
      }
      final imageBytes = await imageFile.readAsBytes();
      imageValue = base64Encode(imageBytes);
      LogService.instance.info('[Kling] 已加载并编码本地参考图: $referenceImagePath');
    }

    // 构建请求体，与文生图相比多了 'image' 字段
    final payload = {
      'prompt': positivePrompt,
      'negative_prompt': negativePrompt,
      'n': count,
      'model_name': apiConfig.model,
      'aspect_ratio': _mapToAspectRatio(width, height),
      'image': imageValue, // 参考图的 URL 或 Base64 编码
    };

    // 创建生成任务并获取任务ID
    final taskId = await _createGenerationTask(payload,apiConfig);
    if (taskId == null) return null;

    // 执行后续的生成流程
    return _executeGenerationFlow(taskId, saveDir,apiConfig);
  }


  /// 执行通用的生成流程：创建任务 -> 轮询状态 -> 下载结果。
  Future<List<String>?> _executeGenerationFlow(String taskId, String saveDir, ApiModel apiConfig) async {
    LogService.instance.success('[Kling] 任务创建成功，ID: $taskId');

    // 轮询任务状态，直到任务完成或失败。
    final resultData = await _pollTaskStatus(taskId, apiConfig);
    if (resultData == null) return null;
    LogService.instance.success('[Kling] 任务状态轮询完成，结果: ${resultData['task_status']}');

    // 检查任务是否成功，并提取图像信息列表
    final imagesInfo = (resultData['task_result'] as Map?)?['images'] as List?;
    if (imagesInfo == null || imagesInfo.isEmpty) {
      LogService.instance.warn('[Kling] 任务已成功，但 API 未返回图像信息。');
      return null;
    }

    // 为每个图像信息创建并行的下载任务
    final downloadFutures = imagesInfo.map((imgInfo) {
      final imageUrl = (imgInfo as Map)['url'] as String?;
      return imageUrl != null ? _downloadImage(imageUrl, saveDir) : Future.value(null);
    });

    // 等待所有下载任务完成，并过滤掉失败的结果(null)。
    final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();

    // 如果有至少一张图片下载成功，则返回路径列表，否则返回 null
    return imagePaths.isNotEmpty ? imagePaths : null;
  }

  /// 向 Kling API 提交请求以创建图像生成任务。
  Future<String?> _createGenerationTask(Map<String, dynamic> payload, ApiModel apiConfig) async {
    final uri = Uri.parse('$_baseUrl/v1/images/generations');
    final headers = {
      'Authorization': 'Bearer ${_generateAuthToken(apiConfig)}',
      'Content-Type': 'application/json'
    };

    try {
      // 发送 POST 请求，并设置30秒超时
      final response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      // 解码响应体
      final data = jsonDecode(utf8.decode(response.bodyBytes));

      // 检查状态码和业务码是否都成功
      if (response.statusCode == 200 && data['code'] == 0) {
        final taskId = data['data']['task_id'] as String;
        return taskId;
      }
      
      // 如果失败，记录错误日志
      LogService.instance.error('[Kling] 创建任务失败: ${response.statusCode} ${response.body}');
      return null;
    } catch (e, s) {
      // 捕获网络或超时等异常
      LogService.instance.error('[Kling] 创建任务时发生网络或超时错误', e, s);
      return null;
    }
  }

  /// 轮询任务状态，直到任务完成、失败或超时。
  Future<Map<String, dynamic>?> _pollTaskStatus(String taskId, ApiModel apiConfig) async {
    const maxRetries = 60; // 最大重试次数（60次 * 5秒 = 5分钟）
    const waitInterval = Duration(seconds: 5); // 每次轮询的间隔时间

    for (var i = 0; i < maxRetries; i++) {
      // 等待指定间隔
      await Future.delayed(waitInterval);

      final uri = Uri.parse('$_baseUrl/v1/images/generations/$taskId');
      final headers = {'Authorization': 'Bearer ${_generateAuthToken(apiConfig)}'};

      try {
        // 发送 GET 请求查询任务状态
        final response = await client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (response.statusCode == 200 && data['code'] == 0) {
          final status = data['data']['task_status'] as String;
          LogService.instance.info('[Kling] 轮询任务状态: $status');
          // 如果任务成功，返回结果数据
          if (status == 'succeed') {
            return data['data'];
          }
          // 如果任务明确失败，记录错误并中止轮询
          if (status == 'failed') {
            LogService.instance.error('[Kling] 任务失败: ${data['data']['task_status_msg']}');
            return null;
          }
        } else {
          // 记录轮询请求本身的失败
          LogService.instance.warn('[Kling] 轮询请求失败或返回错误: ${response.statusCode} ${response.body}');
        }
      } catch (e, s) {
        // 记录轮询过程中的网络或解析错误
        LogService.instance.error('[Kling] 轮询期间发生网络或解析错误', e, s);
      }
    }
    
    // 如果循环结束任务仍未完成，则视为超时
    LogService.instance.error('[Kling] 轮询超时。');
    return null;
  }

  /// 从给定的 URL 下载图片并保存到本地。
  Future<String?> _downloadImage(String url, String saveDir) async {
    try {
      LogService.instance.info('[Kling] 正在下载图片: $url');
      // 发送 GET 请求下载图片，设置120秒超时
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        // 从 URL 中提取或默认使用 .png 作为文件扩展名
        final extension = p.extension(Uri.parse(url).path).isNotEmpty
            ? p.extension(Uri.parse(url).path)
            : '.png';
        // 使用 UUID 生成唯一文件名
        final imagePath = p.join(saveDir, '${const Uuid().v4()}$extension');
        // 确保保存目录存在
        await Directory(saveDir).create(recursive: true);
        // 将图片数据写入文件
        await File(imagePath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[Kling] 图片已保存到: $imagePath');
        return imagePath;
      }
      LogService.instance.error('[Kling] 从 $url 下载图片失败。状态码: ${response.statusCode}');
      return null;
    } catch (e, s) {
      LogService.instance.error('[Kling] 从 $url 下载图片时出错', e, s);
      return null;
    }
  }

  /// 生成用于身份验证的 JWT (JSON Web Token)。
  String _generateAuthToken(ApiModel apiConfig) {
    final accessKey = apiConfig.accessKey;
    final secretKey = apiConfig.secretKey;

    // 校验 AK/SK 是否存在
    if (accessKey == null || accessKey.isEmpty) {
      throw Exception('Kling 平台需要有效的 Access Key');
    }
    if (secretKey == null || secretKey.isEmpty) {
      throw Exception('Kling 平台需要有效的 Secret Key');
    }

    // 定义 JWT 的头部
    final header = {'alg': 'HS256'};
    // 定义 JWT 的载荷 (payload)
    final payload = {
      'iss': accessKey, // 签发者为 Access Key
      'exp': DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000, // 过期时间：30分钟后
      'nbf': DateTime.now().subtract(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000, // 生效时间：5秒前
    };

    // 使用 dart_jsonwebtoken 库创建和签名 JWT
    final jwt = JWT(payload, header: header);
    final token = jwt.sign(SecretKey(secretKey), algorithm: JWTAlgorithm.HS256, noIssueAt: true);

    return token;
  }

  /// 将宽高尺寸映射到 API 支持的宽高比字符串。
  String _mapToAspectRatio(int width, int height) {
    // 优先匹配 API 文档中提到的精确尺寸
    if (width == 1280 && height == 720) return '16:9';
    if (width == 720 && height == 1280) return '9:16';
    if (width == 1024 && height == 1024) return '1:1';
    if (width == 1024 && height == 768) return '4:3';
    if (width == 768 && height == 1024) return '3:4';

    // 如果不完全匹配，则根据比例进行模糊匹配，允许微小误差
    final ratio = width / height;
    if ((ratio - 16 / 9).abs() < 0.05) return '16:9';
    if ((ratio - 9 / 16).abs() < 0.05) return '9:16';
    if ((ratio - 1).abs() < 0.05) return '1:1';
    if ((ratio - 4 / 3).abs() < 0.05) return '4:3';
    if ((ratio - 3 / 4).abs() < 0.05) return '3:4';
    if ((ratio - 3 / 2).abs() < 0.05) return '3:2';
    if ((ratio - 2 / 3).abs() < 0.05) return '2:3';
    if ((ratio - 21 / 9).abs() < 0.05) return '21:9';

    // 如果都无法匹配，则返回一个最常用的默认比例
    LogService.instance.warn('[Kling] 未找到精确的宽高比匹配，已回退到默认值 16:9');
    return '16:9';
  }
}