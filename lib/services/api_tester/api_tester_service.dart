import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../models/api_model.dart';
import '../drawing_service/drawing_service.dart';
import '../llm_service/llm_service.dart';
import '../video_service/video_service.dart';

/// 用于封装测试结果的简单类
class TestResult {
  final bool success;
  final String message;

  TestResult(this.success, this.message);
}

/// 负责对不同类型的API进行连接性测试的服务
class ApiTesterService {
  // 使用单例模式
  ApiTesterService._();
  static final ApiTesterService instance = ApiTesterService._();

  /// 测试语言模型（LLM）API配置
  Future<TestResult> testLanguageApi(ApiModel apiConfig) async {
    try {
      // 使用一个简单、无害的提示词进行测试
      final response = await LlmService.instance.requestCompletion(
        systemPrompt: 'You are a helpful assistant.',
        messages: [{'role': 'user', 'content': 'Hi, please respond with only the words "test successful"'}],
        apiConfig: apiConfig,
      );

      // 检查响应是否符合预期
      if (response.trim().toLowerCase().contains('test successful')) {
        return TestResult(true, '测试成功: API返回了预期内容。');
      } else {
        // 请求成功，但内容不符合预期，也算成功，但给出提示
        return TestResult(true, '测试已通，但API返回内容非预期: "${response.trim()}"');
      }
    } catch (e) {
      // 捕获并返回任何在请求过程中发生的异常
      return TestResult(false, '测试失败: ${e.toString()}');
    }
  }

  /// 测试绘画（Drawing）API配置
  Future<TestResult> testDrawingApi(ApiModel apiConfig) async {
    Directory? tempDir;
    try {
      // 为测试图像创建一个临时目录，测试结束后会删除
      tempDir = await getTemporaryDirectory();
      final testSaveDir = Directory(p.join(tempDir.path, 'api_test_images'));
      if (await testSaveDir.exists()) {
        await testSaveDir.delete(recursive: true);
      }
      await testSaveDir.create(recursive: true);

      // 使用简单提示词和最小尺寸进行测试，以节省资源和时间
      final imagePaths = await DrawingService.instance.generateImages(
        positivePrompt: 'a white cat on a white background',
        negativePrompt: 'blurry, ugly, text, watermark',
        saveDir: testSaveDir.path,
        count: 1,
        width: 1024, 
        height: 1024,
        apiConfig: apiConfig,
      );

      // 测试结束后，立即清理临时文件
      if (await testSaveDir.exists()) {
         await testSaveDir.delete(recursive: true);
      }

      // 检查是否成功返回了图像路径
      if (imagePaths != null && imagePaths.isNotEmpty) {
        return TestResult(true, '测试成功: API成功生成并返回了 ${imagePaths.length} 张图片的路径。');
      } else {
        return TestResult(false, '测试失败: API调用成功，但未返回任何图片。');
      }
    } catch (e) {
       // 如果过程中发生错误，也尝试清理临时文件
      if (tempDir != null) {
        final testSaveDir = Directory(p.join(tempDir.path, 'api_test_images'));
        if (await testSaveDir.exists()) {
          await testSaveDir.delete(recursive: true);
        }
      }
      // 捕获并返回异常
      return TestResult(false, '测试失败: ${e.toString()}');
    }
  }
  /// 测试视频（Video）API配置
  Future<TestResult> testVideoApi(ApiModel apiConfig) async {
    Directory? tempDir;
    try {
      // 为测试视频创建一个临时目录
      tempDir = await getTemporaryDirectory();
      final testSaveDir = Directory(p.join(tempDir.path, 'api_test_videos'));
      if (await testSaveDir.exists()) {
        await testSaveDir.delete(recursive: true);
      }
      await testSaveDir.create(recursive: true);

      // 使用简单提示词进行测试
      final videoPaths = await VideoService.instance.generateVideo(
        positivePrompt: 'a cute cat running on the grass',
        saveDir: testSaveDir.path,
        count: 1,
        resolution: '720P',
        apiConfig: apiConfig,
      );

      // 测试结束后，立即清理临时文件
      if (await testSaveDir.exists()) {
         await testSaveDir.delete(recursive: true);
      }

      // 检查是否成功返回了视频路径
      if (videoPaths != null && videoPaths.isNotEmpty) {
        return TestResult(true, '测试成功: API成功生成并返回了 ${videoPaths.length} 个视频的路径。');
      } else {
        return TestResult(false, '测试失败: API调用成功，但未返回任何视频。');
      }
    } catch (e) {
       // 如果过程中发生错误，也尝试清理临时文件
      if (tempDir != null) {
        final testSaveDir = Directory(p.join(tempDir.path, 'api_test_videos'));
        if (await testSaveDir.exists()) {
          await testSaveDir.delete(recursive: true);
        }
      }
      // 捕获并返回异常
      return TestResult(false, '测试失败: ${e.toString()}');
    }
  }
}