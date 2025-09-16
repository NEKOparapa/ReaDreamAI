// lib/services/drawing_service/platforms/liblib_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/api_model.dart';
import '../drawing_platform.dart';

/// Liblib 平台的具体实现。
class LiblibPlatform implements DrawingPlatform {
  final http.Client client;
  // final ApiModel apiConfig; // <--- 移除成员变量

  // 将 Liblib 平台的 Base URL 定义为固定的静态常量。
  static const String _baseUrl = 'https://openapi.liblibai.cloud';
  // 定义 API 的 URI 路径为常量，方便管理。
  static const _txt2imgUri = '/api/generate/webui/text2img/ultra';
  static const _img2imgUri = '/api/generate/webui/img2img/ultra';
  static const _statusUri = '/api/generate/webui/status';

  // 构造函数不再接收 apiConfig
  LiblibPlatform({required this.client});

  /// 为 API 请求生成签名。
  Map<String, String> _generateSignature(String uri, ApiModel apiConfig) { // <--- 接收 apiConfig
    final accessKey = apiConfig.accessKey;
    final secretKey = apiConfig.secretKey;
    if (accessKey == null || accessKey.isEmpty) {
      throw Exception('Liblib 平台需要在 API 配置中提供非空的 Access Key。');
    }
    if (secretKey == null || secretKey.isEmpty) {
      throw Exception('Liblib 平台需要在 API 配置中提供非空的 Secret Key。');
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch).toString();
    final nonce = const Uuid().v4();
    final contentToSign = '$uri&$timestamp&$nonce';

    final hmac = Hmac(sha1, utf8.encode(secretKey));
    final digest = hmac.convert(utf8.encode(contentToSign));
    final signature = base64Url.encode(digest.bytes).replaceAll('=', '');

    return {
      'AccessKey': accessKey,
      'Timestamp': timestamp,
      'SignatureNonce': nonce,
      'Signature': signature,
    };
  }

  // ... ( _mapToAspectRatio 和 _isUrl 方法不变 )

  @override
  Future<List<String>?> generate({
    required String positivePrompt,
    required String negativePrompt,
    required String saveDir,
    required int count,
    required int width,
    required int height,
    required ApiModel apiConfig, // <--- apiConfig 作为参数传入
    String? referenceImagePath,
  }) async {
    String? taskUuid;

    if (referenceImagePath != null && _isUrl(referenceImagePath)) {
      print('[LiblibAI] 📸 检测到参考图URL，切换到图生图模式。');
      taskUuid = await _createImg2ImgTask(positivePrompt, negativePrompt, count, referenceImagePath, apiConfig); // <--- 传递 apiConfig
    } 
    else {
      if (referenceImagePath != null) {
        print('[LiblibAI] ⚠️ 提供的参考图路径不是一个有效的URL，将忽略并使用文生图模式。');
      }
      print('[LiblibAI] ✍️ 使用文生图模式。');
      taskUuid = await _createText2ImgTask(positivePrompt, negativePrompt, count, width, height, apiConfig); // <--- 传递 apiConfig
    }

    if (taskUuid == null) return null;

    final resultData = await _pollTaskStatus(taskUuid, apiConfig); // <--- 传递 apiConfig
    if (resultData == null) return null;

    final images = resultData['images'] as List?;
    if (images == null || images.isEmpty) {
      print('[LiblibAI] ❓ 任务已成功，但 API 未返回图像信息。');
      return null;
    }

    final downloadFutures = images.map((imgInfo) {
      final imageUrl = (imgInfo as Map)['imageUrl'] as String?;
      return imageUrl != null ? _downloadImage(imageUrl, saveDir) : Future.value(null);
    });

    final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
    return imagePaths.isNotEmpty ? imagePaths : null;
  }

  /// 创建文生图任务
  Future<String?> _createText2ImgTask(String prompt, String negativePrompt, int count, int width, int height, ApiModel apiConfig) async { // <--- 接收 apiConfig
    print('[LiblibAI] 🚀 正在创建文生图任务...');
    final authParams = _generateSignature(_txt2imgUri, apiConfig); // <--- 传递 apiConfig
    final uri = Uri.parse('$_baseUrl$_txt2imgUri').replace(queryParameters: authParams);

    final templateUuid = apiConfig.model; // 使用传入的 apiConfig
    if (templateUuid.isEmpty) {
      throw Exception('Liblib 平台进行文生图，需要在 API 配置的“模型”字段中提供模板 UUID。');
    }

    final payload = {
      'templateUuid': templateUuid,
      'generateParams': {
        'prompt': prompt,
        'negativePrompt': negativePrompt,
        'imgCount': count,
        'aspectRatio': _mapToAspectRatio(width, height),
        'steps': 30,
      }
    };

    final response = await client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['code'] == 0) {
      final taskUuid = data['data']['generateUuid'] as String;
      print('[LiblibAI] ✅ 文生图任务创建成功，任务 UUID: $taskUuid');
      return taskUuid;
    }

    print('[LiblibAI] ❌ 创建文生图任务失败: ${response.statusCode} ${response.body}');
    return null;
  }

  /// 创建图生图任务
  Future<String?> _createImg2ImgTask(String prompt, String negativePrompt, int count, String imageUrl, ApiModel apiConfig) async { // <--- 接收 apiConfig
    print('[LiblibAI] 🚀 正在创建图生图任务...');
    final authParams = _generateSignature(_img2imgUri, apiConfig); // <--- 传递 apiConfig
    final uri = Uri.parse('$_baseUrl$_img2imgUri').replace(queryParameters: authParams);

    const String templateUuid = '07e00af4fc464c7ab55ff906f8acf1b7';

    final payload = {
      'templateUuid': templateUuid, 
      'generateParams': {
        'prompt': prompt,
        'negativePrompt': negativePrompt, 
        'sourceImage': imageUrl,
        'imgCount': count,
      }
    };

    final response = await client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['code'] == 0) {
      final taskUuid = data['data']['generateUuid'] as String;
      print('[LiblibAI] ✅ 图生图任务创建成功，任务 UUID: $taskUuid');
      return taskUuid;
    }

    print('[LiblibAI] ❌ 创建图生图任务失败: ${response.statusCode} ${response.body}');
    return null;
  }

  /// 轮询任务状态。
  Future<Map<String, dynamic>?> _pollTaskStatus(String taskUuid, ApiModel apiConfig) async { // <--- 接收 apiConfig
    print('[LiblibAI] ⏳ 正在轮询任务状态，UUID: $taskUuid...');
    const maxRetries = 40;
    const waitInterval = Duration(seconds: 5);
    
    for (var i = 0; i < maxRetries; i++) {
      await Future.delayed(waitInterval);

      final authParams = _generateSignature(_statusUri, apiConfig); // <--- 传递 apiConfig
      final uri = Uri.parse('$_baseUrl$_statusUri').replace(queryParameters: authParams);
      final response = await client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'generateUuid': taskUuid}));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['code'] == 0) {
        final status = data['data']['generateStatus'] as int;
        print('[LiblibAI] 轮询 ${i + 1}/$maxRetries: 状态码为 "$status"');
        if (status == 5) {
          print('[LiblibAI] ✅ 任务成功！');
          return data['data'];
        }
        if (status == 2) {
          print('[LiblibAI] ⏳ 任务仍在进行中，继续轮询...');
          continue;
        }
        if (status == 3 || status == 4) {
          print('[LiblibAI] ❌ 任务失败: ${data['data']['generateMsg']}');
          return null;
        }
      } else {
        print('[LiblibAI] ⚠️ 轮询请求失败或返回错误: ${response.body}');
      }
    }
    print('[LiblibAI] ❌ 轮询超时。');
    return null;
  }

  // ... ( _downloadImage, _mapToAspectRatio, _isUrl 方法保持不变，因为它们不使用 apiConfig )
  String _mapToAspectRatio(int width, int height) {
    if (width == 1024 && height == 1024) return 'square';
    if (width == 768 && height == 1024) return 'portrait';
    if (width == 1280 && height == 720) return 'landscape';
    return 'square';
  }
  
  bool _isUrl(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<String?> _downloadImage(String url, String saveDir) async {
    try {
      print('[LiblibAI] 📥 正在下载图片: $url');
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final extension = p.extension(Uri.parse(url).path).isNotEmpty ? p.extension(Uri.parse(url).path) : '.png';
        final imagePath = p.join(saveDir, '${const Uuid().v4()}$extension');
        await Directory(saveDir).create(recursive: true);
        await File(imagePath).writeAsBytes(response.bodyBytes);
        print('[LiblibAI] ✅ 图片已保存到: $imagePath');
        return imagePath;
      }
      return null;
    } catch(e) {
      print('[LiblibAI] ❌ 从 $url 下载图片时出错: $e');
      return null;
    }
  }
}