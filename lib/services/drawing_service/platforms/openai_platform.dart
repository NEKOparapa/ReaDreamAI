// lib/services/drawing_service/platforms/openai_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../base/log/log_service.dart'; 
import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// 自定义（OpenAI格式）平台的具体实现。
class OpenAiPlatform implements DrawingPlatform {
  final http.Client client; // HTTP客户端，用于发送网络请求

  OpenAiPlatform({required this.client});

  /// 核心生成方法，根据是否有参考图来决定调用文生图或图生图
  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig, 
    String? referenceImagePath, // 可选的参考图路径
  }) async {
    // 检查参考图路径是否存在且不为空
    if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
      // 如果有参考图，则调用图生图方法
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
      // 否则，调用文生图方法
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

  /// 处理文生图 (Text-to-Image) 请求
  Future<List<String>?> _generateTextToImage({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig, 
  }) async {
    // 记录日志：开始请求
    LogService.instance.info('[OpenAI - Txt2Img] 开始请求生成图像...');
    
    // 构建API端点URL
    final endpoint = Uri.parse('${apiConfig.url}/images/generations');
    
    // 设置请求头，包含授权信息和内容类型
    final headers = {
      "Authorization": "Bearer ${apiConfig.apiKey}",
      "Content-Type": "application/json",
    };

    // 构建请求体 (JSON)
    // 注意：官方OpenAI API不支持 negative_prompt，但许多兼容API支持
    final payload = {
      "prompt": positivePrompt,
      "negative_prompt": negativePrompt,
      "model": apiConfig.model,
      "size": "${width}x${height}",
      "n": count,
      "response_format": "b64_json", // 请求返回Base64编码的图片数据
    };

    try {
      // 发送POST请求，并设置5分钟超时
      final response = await client
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 5));

      // 处理API的响应
      return _processResponse(response, saveDir);
    } catch (e, st) {
      // 记录错误日志
      LogService.instance.error('[OpenAI - Txt2Img] 生成图像时发生错误', e, st);
      return null;
    }
  }

  /// 处理图生图 (Image-to-Image) 请求
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
    LogService.instance.info('[OpenAI - Img2Img] 开始请求生成图像...');
    
    // 许多兼容API在同一端点支持图生图
    final endpoint = Uri.parse('${apiConfig.url}/images/generations');
    final headers = {"Authorization": "Bearer ${apiConfig.apiKey}"};

    try {
      // 获取图片数据，自动处理URL或本地路径
      final imageBytes = await _getImageBytes(referenceImagePath);
      if (imageBytes == null) {
        throw Exception('无法获取参考图片数据。');
      }

      // 创建一个 multipart 请求，用于同时上传文件和表单数据
      final request = http.MultipartRequest('POST', endpoint);
      request.headers.addAll(headers);

      // 添加文本字段到请求中
      request.fields.addAll({
        'prompt': positivePrompt,
        'model': apiConfig.model,
        'size': '${width}x${height}',
        'n': count.toString(),
        'response_format': 'b64_json',
      });

      // 添加图片文件到请求中
      request.files.add(http.MultipartFile.fromBytes(
        'image', // 字段名通常是 'image'
        imageBytes,
        filename: 'reference_image.png', // 提供一个文件名
      ));
      
      // 发送请求并获取响应流
      final streamedResponse = await client.send(request).timeout(const Duration(minutes: 5));
      // 从响应流中创建完整的HTTP响应
      final response = await http.Response.fromStream(streamedResponse);
      
      // 处理API的响应
      return _processResponse(response, saveDir);

    } catch (e, st) {
      // 记录错误日志
      LogService.instance.error('[OpenAI - Img2Img] 生成图像时发生错误', e, st);
      return null;
    }
  }

  /// 统一处理API响应，解码并保存图片
  Future<List<String>?> _processResponse(http.Response response, String saveDir) async {
    // 检查HTTP状态码是否为200 (成功)
    if (response.statusCode != 200) {
      final errorMsg = '[OpenAI] API 请求失败 (${response.statusCode}): ${response.body}';
      LogService.instance.error(errorMsg);
      throw Exception(errorMsg);
    }

    // 解码响应体
    final responseData = jsonDecode(utf8.decode(response.bodyBytes));
    final dataList = responseData['data'] as List?;

    // 检查响应中是否包含图像数据
    if (dataList == null || dataList.isEmpty) {
      final errorMsg = '[OpenAI] API 未返回图像数据。响应: ${response.body}';
      LogService.instance.error(errorMsg);
      throw Exception('OpenAI API 未返回图像数据');
    }

    LogService.instance.success('[OpenAI] 成功获取 Base64 图像数据，准备保存...');

    // 确保保存目录存在
    await Directory(saveDir).create(recursive: true);
    final List<String> savedImagePaths = [];

    // 遍历返回的每张图片数据
    for (final item in dataList) {
      final b64Json = (item as Map<String, dynamic>)['b64_json'] as String?;
      if (b64Json != null && b64Json.isNotEmpty) {
        try {
          // 解码Base64字符串为图片字节
          final imageBytes = base64Decode(b64Json);
          // 生成唯一文件名并拼接完整路径
          final imagePath = p.join(saveDir, '${const Uuid().v4()}.png');
          // 将图片字节写入文件
          await File(imagePath).writeAsBytes(imageBytes);
          savedImagePaths.add(imagePath);
          LogService.instance.success('[OpenAI] 图片已保存到: $imagePath');
        } catch (e) {
          LogService.instance.error('[OpenAI] 解码或保存 Base64 图像时出错', e);
        }
      } else {
        LogService.instance.warn('[OpenAI] 响应中的某个条目未找到 b64_json 数据。');
      }
    }

    // 如果成功保存了至少一张图片，则返回路径列表，否则返回null
    return savedImagePaths.isNotEmpty ? savedImagePaths : null;
  }

  /// 从本地路径或URL获取图片的字节数据
  Future<Uint8List?> _getImageBytes(String pathOrUrl) async {
    try {
      // 判断是URL还是本地路径
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        // 从 URL 下载
        LogService.instance.info('[OpenAI - Util] 正在从URL下载参考图: $pathOrUrl');
        final response = await client.get(Uri.parse(pathOrUrl));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        } else {
          LogService.instance.error('[OpenAI - Util] 下载图片失败 (${response.statusCode})');
          return null;
        }
      } else {
        // 从本地文件读取
        LogService.instance.info('[OpenAI - Util] 正在读取本地参考图: $pathOrUrl');
        final file = File(pathOrUrl);
        if (await file.exists()) {
          return await file.readAsBytes();
        } else {
           LogService.instance.error('[OpenAI - Util] 本地文件不存在: $pathOrUrl');
          return null;
        }
      }
    } catch (e) {
      LogService.instance.error('[OpenAI - Util] 获取图片字节时发生错误', e);
      return null;
    }
  }
}