// lib/services/drawing_service/platforms/comfyui_platform.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../base/api_model.dart';
import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../drawing_platform.dart';
import '../../../base/log/log_service.dart'; 

/// ComfyUI 平台的具体实现。
class ComfyUiPlatform implements DrawingPlatform {
  final http.Client client; 
  final ConfigService _configService = ConfigService(); 

  ComfyUiPlatform({required this.client});

  /// 生成图像的入口方法。
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
    // 1. 根据用户输入和配置准备 ComfyUI 的工作流 (workflow) JSON
    final workflow = await _prepareWorkflow(positivePrompt, negativePrompt, count, width, height);
    if (workflow == null) return null; // 如果工作流准备失败，则中止

    // 2. 为本次会话生成一个唯一的客户端 ID
    final clientId = const Uuid().v4();

    // 3. 将工作流提交到 ComfyUI 队列，并获取任务 ID (promptId)
    final promptId = await _queuePrompt(workflow, clientId, apiConfig); 
    if (promptId == null) return null; // 如果提交失败，则中止

    // 4. 通过 WebSocket 等待任务执行完成
    final success = await _waitForCompletion(promptId, clientId, apiConfig); 
    if (!success) return null; // 如果执行失败或超时，则中止

    // 5. 任务完成后，通过任务 ID 获取其执行历史记录
    final history = await _getHistory(promptId, apiConfig); 
    if (history == null) return null; // 如果获取历史记录失败，则中止

    // 6. 从历史记录中解析出图像信息，并下载它们到指定目录
    return await _downloadImagesFromHistory(history, saveDir, apiConfig); 
  }

  /// 准备 ComfyUI 工作流。
  Future<Map<String, dynamic>?> _prepareWorkflow(String positive, String negative, int count, int width, int height) async {
    // 从配置中获取用户选择的工作流类型代号 ('system' 或 'custom')
    final workflowType = _configService.getSetting<String>('comfyui_workflow_type', appDefaultConfigs['comfyui_workflow_type']);
    String workflowPath;
    bool isAsset; // 标记工作流是来自应用内部资源(asset)还是外部文件系统

    // 根据工作流类型，确定工作流文件的具体路径
    if (workflowType == 'custom') {
      // 如果是自定义工作流，从配置中读取用户指定的文件路径
      workflowPath = _configService.getSetting<String>('comfyui_custom_workflow_path', '');
      if (workflowPath.isEmpty) {
        throw Exception('未设置自定义ComfyUI工作流路径。');
      }
      isAsset = false; // 标记为非应用内资源
    } else {
      // 如果是系统预设工作流，从配置中读取对应的应用内资源路径
      workflowPath = _configService.getSetting<String>('comfyui_system_workflow_path', appDefaultConfigs['comfyui_system_workflow_path']);
      isAsset = true; // 标记为应用内资源
    }

    try {
      String jsonString;
      // 根据路径来源加载工作流JSON文件内容
      if (isAsset) {
        jsonString = await rootBundle.loadString(workflowPath);
      } else {
        final file = File(workflowPath);
        if (!await file.exists()) {
          throw Exception('自定义工作流文件未找到: $workflowPath');
        }
        jsonString = await file.readAsString();
      }

      // 将JSON字符串解析为Dart中的Map对象
      final workflow = jsonDecode(jsonString) as Map<String, dynamic>;

      // 从配置服务获取需要修改的目标节点ID和字段名
      final positiveNodeId = _configService.getSetting<String>('comfyui_positive_prompt_node_id', appDefaultConfigs['comfyui_positive_prompt_node_id']);
      final positiveField = _configService.getSetting<String>('comfyui_positive_prompt_field', appDefaultConfigs['comfyui_positive_prompt_field']);
      final negativeNodeId = _configService.getSetting<String>('comfyui_negative_prompt_node_id', appDefaultConfigs['comfyui_negative_prompt_node_id']);
      final negativeField = _configService.getSetting<String>('comfyui_negative_prompt_field', appDefaultConfigs['comfyui_negative_prompt_field']);
      
      // 获取图片数量
      final batchSizeNodeId = _configService.getSetting<String>('comfyui_batch_size_node_id', appDefaultConfigs['comfyui_batch_size_node_id']);
      final latentImageNodeId = _configService.getSetting<String>('comfyui_latent_image_node_id', appDefaultConfigs['comfyui_latent_image_node_id']);
      
      // 获取图片大小
      final batchSizeField = _configService.getSetting<String>('comfyui_batch_size_field', appDefaultConfigs['comfyui_batch_size_field']);
      final widthField = _configService.getSetting<String>('comfyui_latent_width_field', appDefaultConfigs['comfyui_latent_width_field']);
      final heightField = _configService.getSetting<String>('comfyui_latent_height_field', appDefaultConfigs['comfyui_latent_height_field']);

      // 在工作流Map中找到对应的节点，并更新其输入(inputs)值
      workflow[positiveNodeId]['inputs'][positiveField] = positive;
      workflow[negativeNodeId]['inputs'][negativeField] = negative;
      
      // 修改批处理数量
      workflow[batchSizeNodeId]['inputs'][batchSizeField] = count;

      // 修改图像尺寸
      workflow[latentImageNodeId]['inputs'][widthField] = width;
      workflow[latentImageNodeId]['inputs'][heightField] = height;

      return workflow;
    } catch (e, s) {
      LogService.instance.error('加载或解析工作流文件时出错: $workflowPath', e, s);
      throw Exception('ComfyUI 工作流文件加载或解析失败于 $workflowPath: $e');
    }
  }
  
  /// 将准备好的工作流提交到 ComfyUI 的任务队列。
  Future<String?> _queuePrompt(Map<String, dynamic> workflow, String clientId, ApiModel apiConfig) async {
    LogService.instance.info('[ComfyUI] 🚀 正在提交工作流...');
    // 构建提交工作流的API端点URL
    final uri = Uri.parse('${apiConfig.url}/prompt');

    try {
      // 发送POST请求，请求体中包含工作流和客户端ID
      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
      );

      // 检查HTTP响应状态码
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final promptId = data['prompt_id'] as String;
        LogService.instance.success('[ComfyUI] ✅ 工作流提交成功，任务 ID: $promptId');
        return promptId; // 成功则返回任务ID
      } else {
        LogService.instance.error('[ComfyUI] ❌ 工作流提交失败: ${response.statusCode} ${response.body}');
        return null; // 失败则返回null
      }
    } catch (e, s) {
      LogService.instance.error('[ComfyUI] ❌ 提交工作流时发生网络错误', e, s);
      return null;
    }
  }

  /// 通过 WebSocket 监听任务执行状态，等待其完成。
  Future<bool> _waitForCompletion(String promptId, String clientId, ApiModel apiConfig) async {
    // 创建一个Completer，用于异步地返回任务是否成功的结果
    final completer = Completer<bool>();
    // 将API的http/https协议替换为ws/wss来构建WebSocket连接地址
    final wsUri = Uri.parse('${apiConfig.url.replaceFirst('http', 'ws')}/ws?clientId=$clientId');
    final channel = WebSocketChannel.connect(wsUri);

    LogService.instance.info('[ComfyUI] ⏳ 正在建立 WebSocket 连接并等待任务完成...');

    // 监听WebSocket消息流
    var sub = channel.stream.listen(
      (message) async {
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'] as String;
        
          final eventData = data['data'];

          // 确保只处理与当前提交任务相关的事件
          if (eventData != null && eventData['prompt_id'] != null && eventData['prompt_id'] != promptId) {
            return;
          }
          
          // 根据从服务端接收到的事件类型进行处理
          switch (type) {
            case 'executing':
              // 当 'node' 字段为 null 时，表示整个工作流执行完毕
              if (eventData['node'] == null) {
                if (!completer.isCompleted) completer.complete(true);
              }
              break;
            case 'execution_cached':
              // 表示某些节点使用了缓存结果，流程正常继续，无需特殊处理
              break;
            case 'execution_error':
              // 任务执行出错
              LogService.instance.error('[ComfyUI] ❌ 任务执行出错: $eventData');
              if (!completer.isCompleted) completer.complete(false);
              break;
            case 'progress':
              // 任务进度更新事件 (当前代码中未详细处理，仅作日志记录)
              // final progressData = eventData;
              // LogService.instance.info('[ComfyUI] 任务进度: ${progressData['value']}/${progressData['max']}');
              break;
          }
        } 
      },
      onError: (error, stackTrace) {
        // WebSocket连接发生错误
        LogService.instance.error('[ComfyUI] ❌ WebSocket 连接出错', error, stackTrace);
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        // WebSocket连接正常关闭
        LogService.instance.info('[ComfyUI] WebSocket 连接已关闭。');
        if (!completer.isCompleted) {
          // 有时连接会在收到明确的完成信号前关闭。
          // 我们假设任务可能已完成，后续通过API获取历史记录来最终确认。
          LogService.instance.warn('[ComfyUI] WebSocket 在没有明确完成信号的情况下关闭。假设任务可能已完成，将通过历史记录 API 进行验证。');
          completer.complete(true);
        }
      },
    );

    // 设置一个10分钟的超时，防止因网络或服务器问题导致无限等待
    Future.delayed(const Duration(minutes: 10), () {
      if (!completer.isCompleted) {
        LogService.instance.error('[ComfyUI] ❌ 等待任务完成超时。');
        sub.cancel();
        channel.sink.close();
        completer.complete(false);
      }
    });

    // 等待completer完成，并获取最终结果
    final success = await completer.future;
    // 清理资源：取消流监听并关闭WebSocket连接
    await sub.cancel();
    await channel.sink.close();
    return success;
  }

  /// 任务完成后，根据任务 ID 获取其完整的历史记录，包括生成的图像信息。
  Future<Map<String, dynamic>?> _getHistory(String promptId, ApiModel apiConfig) async {
    LogService.instance.info('[ComfyUI] 正在获取任务历史记录，ID: $promptId');
    final uri = Uri.parse('${apiConfig.url}/history/$promptId');
    try {
      final response = await client.get(uri);
      if (response.statusCode == 200) {
        final history = jsonDecode(response.body);
        // ComfyUI返回的历史记录是一个以promptId为键的Map
        return history[promptId] as Map<String, dynamic>?;
      }
      LogService.instance.error('[ComfyUI] ❌ 获取历史记录失败: ${response.statusCode}');
      return null;
    } catch (e, s) {
      LogService.instance.error('[ComfyUI] ❌ 获取历史记录时发生网络错误', e, s);
      return null;
    }
  }

  /// 从历史记录中解析并下载所有生成的图像。
  Future<List<String>?> _downloadImagesFromHistory(Map<String, dynamic> history, String saveDir, ApiModel apiConfig) async {
    // 用于存放所有图片下载任务的Future列表
    final List<Future<String?>> downloadFutures = [];
    final outputs = history['outputs'] as Map<String, dynamic>;

    // 遍历历史记录中的所有输出节点
    for (final nodeOutput in outputs.values) {
      // 检查节点输出是否包含 'images' 字段
      if ((nodeOutput as Map).containsKey('images')) {
        for (final imageInfo in nodeOutput['images']) {
          final filename = imageInfo['filename'] as String;
          final subfolder = imageInfo['subfolder'] as String;
          final type = imageInfo['type'] as String;
          // 为每张图片创建一个异步下载任务，并添加到列表中
          downloadFutures.add(_downloadImage(filename, subfolder, type, saveDir,apiConfig));
        }
      }
    }

    if (downloadFutures.isEmpty) {
      LogService.instance.warn('[ComfyUI] ❓ 在历史记录输出中未找到图像。');
      return null;
    }

    // 使用Future.wait并行执行所有下载任务，提高效率
    final imagePaths = (await Future.wait(downloadFutures)).whereType<String>().toList();
    return imagePaths.isNotEmpty ? imagePaths : null;
  }

  /// 下载单张图片并保存到本地。
  Future<String?> _downloadImage(String filename, String subfolder, String type, String saveDir, ApiModel apiConfig) async {
    // 构建 ComfyUI 用于查看/下载图片的URL
    final uri = Uri.parse('${apiConfig.url}/view?filename=$filename&subfolder=$subfolder&type=$type');
    try {
      LogService.instance.info('[ComfyUI] 📥 正在下载图片: $filename');
      // 发送GET请求下载图片，设置60秒超时
      final response = await client.get(uri).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        // 确保保存目录存在
        await Directory(saveDir).create(recursive: true);
        final imagePath = p.join(saveDir, filename);
        // 将下载的二进制数据写入文件
        await File(imagePath).writeAsBytes(response.bodyBytes);
        LogService.instance.success('[ComfyUI] ✅ 图片已保存到: $imagePath');
        return imagePath;
      } else {
        LogService.instance.error('[ComfyUI] ❌ 下载图片 $filename 失败。状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, s) {
      LogService.instance.error('[ComfyUI] ❌ 下载图片 $filename 时出错', e, s);
      return null;
    }
  }
}