// lib/services/video_service/platforms/comfyui_video_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../models/api_model.dart';
import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../video_platform.dart';
import '../../../base/log/log_service.dart';

/// ComfyUI 视频平台的具体实现
class ComfyUiVideoPlatform implements VideoPlatform {
  final http.Client client;
  final ConfigService _configService = ConfigService();

  ComfyUiVideoPlatform({required this.client});

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
    String finalReferenceImagePath;
    // 如果没有传入参考图，进入伪文生视频模式，使用默认图片
    if (referenceImagePath == null || referenceImagePath.isEmpty) {
      LogService.instance.info('[ComfyUI视频] 未提供参考图，进入伪文生视频模式，使用默认图片。');
      // 使用 p.join 保证路径在不同平台上的兼容性
      finalReferenceImagePath = p.join('assets', 'reference_images', 'cute_cat.png');
    } else {
      finalReferenceImagePath = referenceImagePath;
    }

    // 准备工作流
    final workflow = await _prepareVideoWorkflow(
      positivePrompt: positivePrompt,
      count: count,
      resolution: resolution,
      referenceImagePath: finalReferenceImagePath,
      apiConfig: apiConfig,
    );
    if (workflow == null) return null;

    // 生成客户端ID
    final clientId = const Uuid().v4();

    // 提交任务
    final promptId = await _queuePrompt(workflow, clientId, apiConfig);
    if (promptId == null) return null;

    // 等待完成
    final success = await _waitForCompletion(promptId, clientId, apiConfig);
    if (!success) return null;

    // 获取历史记录
    final history = await _getHistory(promptId, apiConfig);
    if (history == null) return null;

    // 下载视频
    return await _downloadVideosFromHistory(history, saveDir, apiConfig);
  }

  /// 准备视频工作流
  Future<Map<String, dynamic>?> _prepareVideoWorkflow({
    required String positivePrompt,
    required int count,
    required String resolution,
    required String referenceImagePath,
    required ApiModel apiConfig,
  }) async {
    // 获取工作流配置
    final workflowType = _configService.getSetting<String>(
      'comfyui_video_workflow_type',
      appDefaultConfigs['comfyui_video_workflow_type'],
    );
    
    String workflowPath;
    bool isAsset;

    if (workflowType == 'custom') {
      workflowPath = _configService.getSetting<String>('comfyui_video_custom_workflow_path', '');
      if (workflowPath.isEmpty) {
        throw Exception('未设置自定义ComfyUI视频工作流路径。');
      }
      isAsset = false;
    } else {
      workflowPath = _configService.getSetting<String>(
        'comfyui_video_workflow_path',
        appDefaultConfigs['comfyui_video_workflow_path'],
      );
      isAsset = true;
    }

    try {
      // 加载工作流文件
      String jsonString;
      if (isAsset) {
        jsonString = await rootBundle.loadString(workflowPath);
      } else {
        final file = File(workflowPath);
        if (!await file.exists()) {
          throw Exception('自定义视频工作流文件未找到: $workflowPath');
        }
        jsonString = await file.readAsString();
      }

      final workflow = jsonDecode(jsonString) as Map<String, dynamic>;

      // 获取节点配置
      final positiveNodeId = _configService.getSetting<String>(
        'comfyui_video_positive_prompt_node_id',
        appDefaultConfigs['comfyui_video_positive_prompt_node_id'],
      );
      final positiveField = _configService.getSetting<String>(
        'comfyui_video_positive_prompt_field',
        appDefaultConfigs['comfyui_video_positive_prompt_field'],
      );
      
      // 解析分辨率 固定为 640p 分辨率
      final dimensions = _parseDimensions('720p');
      // [备用代码] 原先根据传入的 resolution 参数动态解析分辨率
      // final dimensions = _parseDimensions(resolution);
      final sizeNodeId = _configService.getSetting<String>(
        'comfyui_video_size_node_id',
        appDefaultConfigs['comfyui_video_size_node_id'],
      );
      final widthField = _configService.getSetting<String>(
        'comfyui_video_width_field',
        appDefaultConfigs['comfyui_video_width_field'],
      );
      final heightField = _configService.getSetting<String>(
        'comfyui_video_height_field',
        appDefaultConfigs['comfyui_video_height_field'],
      );

      // 更新工作流参数
      workflow[positiveNodeId]['inputs'][positiveField] = positivePrompt;
      workflow[sizeNodeId]['inputs'][widthField] = dimensions['width'];
      workflow[sizeNodeId]['inputs'][heightField] = dimensions['height'];

      // 处理参考图片
      final imageNodeId = _configService.getSetting<String>(
        'comfyui_video_image_node_id',
        appDefaultConfigs['comfyui_video_image_node_id'],
      );
      final imageField = _configService.getSetting<String>(
        'comfyui_video_image_field',
        appDefaultConfigs['comfyui_video_image_field'],
      );
      
      // 上传图片并获取文件名
      final uploadedImageName = await _uploadImage(referenceImagePath, apiConfig);
      if (uploadedImageName != null) {
        workflow[imageNodeId]['inputs'][imageField] = uploadedImageName;
      }

      return workflow;
    } catch (e, s) {
      LogService.instance.error('准备视频工作流时出错: $workflowPath', e, s);
      throw Exception('ComfyUI 视频工作流准备失败: $e');
    }
  }

  /// 上传图片到ComfyUI
  Future<String?> _uploadImage(String imagePath, ApiModel apiConfig) async {
    try {
      File imageFile;
      if (imagePath.toLowerCase().startsWith('http')) {
        // 下载网络图片
        final response = await client.get(Uri.parse(imagePath));
        if (response.statusCode != 200) {
          throw Exception('无法下载图片: $imagePath');
        }
        final tempDir = Directory.systemTemp;
        final tempFile = File(p.join(tempDir.path, '${const Uuid().v4()}.png'));
        await tempFile.writeAsBytes(response.bodyBytes);
        imageFile = tempFile;
      } else {
        imageFile = File(imagePath);
        if (!await imageFile.exists()) {
          // 如果文件不存在，尝试作为应用内资源加载
          try {
            final byteData = await rootBundle.load(imagePath);
            final tempDir = Directory.systemTemp;
            final fileName = p.basename(imagePath);
            final tempFile = File(p.join(tempDir.path, '${const Uuid().v4()}_$fileName'));
            await tempFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
            imageFile = tempFile;
            LogService.instance.info('[ComfyUI] 已从应用资源加载图片: $imagePath');
          } catch (e) {
            // 如果作为资源加载也失败，则抛出最终错误
            throw FileSystemException("参考图文件不存在，且从应用资源加载失败", imagePath);
          }
        }
      }

      // 上传到ComfyUI
      final uri = Uri.parse('${apiConfig.url}/upload/image');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final data = jsonDecode(responseBody);
        return data['name'] ?? data['filename'];
      } else {
        LogService.instance.error('[ComfyUI] 上传图片失败: ${response.statusCode}');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[ComfyUI] 上传图片时出错', e, s);
      return null;
    }
  }

  /// 提交工作流
  Future<String?> _queuePrompt(Map<String, dynamic> workflow, String clientId, ApiModel apiConfig) async {
    LogService.instance.info('[ComfyUI视频] 🚀 正在提交视频工作流...');
    final uri = Uri.parse('${apiConfig.url}/prompt');

    try {
      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final promptId = data['prompt_id'] as String;
        LogService.instance.success('[ComfyUI视频] ✅ 工作流提交成功，任务 ID: $promptId');
        return promptId;
      } else {
        LogService.instance.error('[ComfyUI视频] ❌ 工作流提交失败: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[ComfyUI视频] ❌ 提交工作流时发生网络错误', e, s);
      return null;
    }
  }

  /// 等待任务完成
  Future<bool> _waitForCompletion(String promptId, String clientId, ApiModel apiConfig) async {
    final completer = Completer<bool>();
    final wsUri = Uri.parse(apiConfig.url.replaceFirst('http', 'ws') + '/ws?clientId=$clientId');
    final channel = WebSocketChannel.connect(wsUri);

    LogService.instance.info('[ComfyUI视频] ⏳ 正在建立 WebSocket 连接并等待任务完成...');

    var sub = channel.stream.listen(
      (message) async {
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'] as String;
          final eventData = data['data'];

          if (eventData != null && eventData['prompt_id'] != null && eventData['prompt_id'] != promptId) {
            return;
          }
          
          switch (type) {
            case 'executing':
              if (eventData['node'] == null) {
                if (!completer.isCompleted) completer.complete(true);
              }
              break;
            case 'execution_error':
              LogService.instance.error('[ComfyUI视频] ❌ 任务执行出错: $eventData');
              if (!completer.isCompleted) completer.complete(false);
              break;
            case 'progress':
              final value = eventData['value'];
              final max = eventData['max'];
              LogService.instance.info('[ComfyUI视频] 进度: $value/$max');
              break;
          }
        }
      },
      onError: (error, stackTrace) {
        LogService.instance.error('[ComfyUI视频] ❌ WebSocket 连接出错', error, stackTrace);
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        LogService.instance.info('[ComfyUI视频] WebSocket 连接已关闭。');
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      },
    );

    // 设置超时
    Future.delayed(const Duration(minutes: 30), () {
      if (!completer.isCompleted) {
        LogService.instance.error('[ComfyUI视频] ❌ 等待任务完成超时。');
        sub.cancel();
        channel.sink.close();
        completer.complete(false);
      }
    });

    final success = await completer.future;
    await sub.cancel();
    await channel.sink.close();
    return success;
  }

  /// 获取历史记录
  Future<Map<String, dynamic>?> _getHistory(String promptId, ApiModel apiConfig) async {
    LogService.instance.info('[ComfyUI视频] 正在获取任务历史记录...');
    final uri = Uri.parse('${apiConfig.url}/history/$promptId');
    
    try {
      final response = await client.get(uri);
      if (response.statusCode == 200) {
        final history = jsonDecode(response.body);
        return history[promptId] as Map<String, dynamic>?;
      }
      LogService.instance.error('[ComfyUI视频] ❌ 获取历史记录失败: ${response.statusCode}');
      return null;
    } catch (e, s) {
      LogService.instance.error('[ComfyUI视频] ❌ 获取历史记录时发生网络错误', e, s);
      return null;
    }
  }

  /// 从历史记录下载视频
  Future<List<String>?> _downloadVideosFromHistory(Map<String, dynamic> history, String saveDir, ApiModel apiConfig) async {
    final List<Future<String?>> downloadFutures = [];
    final outputs = history['outputs'] as Map<String, dynamic>;
    
    // 添加调试日志
    LogService.instance.info('[ComfyUI视频] 历史记录输出: ${jsonEncode(outputs)}');
    
    for (final nodeId in outputs.keys) {
      final nodeOutput = outputs[nodeId];
      LogService.instance.info('[ComfyUI视频] 节点 $nodeId 输出： ${jsonEncode(nodeOutput)}');
      
      // SaveVideo 节点可能的输出格式
      if (nodeOutput is Map) {
        // 检查各种可能的视频输出键
        final possibleVideoKeys = ['videos', 'gifs', 'video', 'images', 'output'];
        
        for (final key in possibleVideoKeys) {
          if (nodeOutput.containsKey(key)) {
            final items = nodeOutput[key];
            if (items is List) {
              for (final item in items) {
                if (item is Map && item.containsKey('filename')) {
                  final filename = item['filename'] as String;
                  final subfolder = item['subfolder'] ?? '';
                  final type = item['type'] ?? 'output';
                  downloadFutures.add(_downloadVideo(filename, subfolder, type, saveDir, apiConfig));
                }
              }
            }
          }
        }
      }
    }
    
    if (downloadFutures.isEmpty) {
      LogService.instance.warn('[ComfyUI视频] ❓ 在历史记录输出中未找到视频。');
      return null;
    }
    
    final videoPaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
    return videoPaths.isNotEmpty ? videoPaths : null;
  }


  /// 下载单个视频
  Future<String?> _downloadVideo(String filename, String subfolder, String type, String saveDir, ApiModel apiConfig) async {
    final uri = Uri.parse('${apiConfig.url}/view?filename=$filename&subfolder=$subfolder&type=$type');
    
    try {
      LogService.instance.info('[ComfyUI视频] 📥 正在下载视频: $filename');
      final response = await client.get(uri).timeout(const Duration(seconds: 300));
      if (response.statusCode == 200) {
        await Directory(saveDir).create(recursive: true);
        // 保持原始文件扩展名
        final extension = p.extension(filename);
        final videoPath = p.join(saveDir, '${const Uuid().v4()}$extension');
        await File(videoPath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[ComfyUI视频] ✅ 视频已保存到: $videoPath');
        return videoPath;
      } else {
        LogService.instance.error('[ComfyUI视频] ❌ 下载视频 $filename 失败。状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[ComfyUI视频] ❌ 下载视频 $filename 时出错', e, s);
      return null;
    }
  }

  /// 解析分辨率
  Map<String, int> _parseDimensions(String resolution) {
    switch (resolution.toLowerCase()) {
      case '360p':
        return {'width': 640, 'height': 640};
      case '480p':
        return {'width': 480, 'height': 480};
      case '720p':
        return {'width': 720, 'height': 720};
      case '1080p':
        return {'width': 1080, 'height': 1080};
      default:
        return {'width': 480, 'height': 480};
    }
  }
}