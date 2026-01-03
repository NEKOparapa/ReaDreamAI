// lib/services/api_tester/api_tester_service.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../base/api_model.dart';
import '../drawing_service/drawing_service.dart';
import '../llm_service/llm_service.dart';
import '../video_service/video_service.dart';
import '../music_service/music_service.dart';
import '../../base/log/log_service.dart';

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
    Directory? testSaveDir;
    try {
      tempDir = await getTemporaryDirectory();
      testSaveDir = Directory(p.join(tempDir.path, 'api_test_images'));
      if (await testSaveDir.exists()) {
        await testSaveDir.delete(recursive: true);
      }
      await testSaveDir.create(recursive: true);

      final imagePaths = await DrawingService.instance.generateImages(
        positivePrompt: 'a white cat on a white background',
        negativePrompt: 'blurry, ugly, text, watermark',
        saveDir: testSaveDir.path,
        count: 1,
        width: 1024,
        height: 1024,
        apiConfig: apiConfig,
      );

      if (imagePaths != null && imagePaths.isNotEmpty) {
        return TestResult(true, '测试成功: API成功生成并返回了 ${imagePaths.length} 张图片的路径。');
      } else {
        return TestResult(false, '测试失败: API调用成功，但未返回任何图片。');
      }
    } catch (e) {
      return TestResult(false, '测试失败: ${e.toString()}');
    } finally { // 确保清理
      if (testSaveDir != null && await testSaveDir.exists()) {
        try {
          await testSaveDir.delete(recursive: true);
          LogService.instance.info('已删除临时绘画测试目录: ${testSaveDir.path}');
        } catch (e) {
          LogService.instance.error('删除临时绘画测试目录失败: ${testSaveDir.path}', e);
        }
      }
    }
  }

  /// 测试视频（Video）API配置
  Future<TestResult> testVideoApi(ApiModel apiConfig) async {
    Directory? tempDir;
    Directory? testSaveDir;
    try {
      tempDir = await getTemporaryDirectory();
      testSaveDir = Directory(p.join(tempDir.path, 'api_test_videos'));
      if (await testSaveDir.exists()) {
        await testSaveDir.delete(recursive: true);
      }
      await testSaveDir.create(recursive: true);

      final videoPaths = await VideoService.instance.generateVideo(
        positivePrompt: 'a cute cat running on the grass',
        saveDir: testSaveDir.path,
        count: 1,
        resolution: '720P',
        duration: 5,
        apiConfig: apiConfig,
      );

      if (videoPaths != null && videoPaths.isNotEmpty) {
        return TestResult(true, '测试成功: API成功生成并返回了 ${videoPaths.length} 个视频的路径。');
      } else {
        return TestResult(false, '测试失败: API调用成功，但未返回任何视频。');
      }
    } catch (e) {
      return TestResult(false, '测试失败: ${e.toString()}');
    } finally { // 确保清理
      if (testSaveDir != null && await testSaveDir.exists()) {
        try {
          await testSaveDir.delete(recursive: true);
          LogService.instance.info('已删除临时视频测试目录: ${testSaveDir.path}');
        } catch (e) {
          LogService.instance.error('删除临时视频测试目录失败: ${testSaveDir.path}', e);
        }
      }
    }
  }

  /// 测试音乐（Music）API配置
  Future<TestResult> testMusicApi(ApiModel apiConfig) async {
    Directory? tempDir;
    Directory? testSaveDir; // 在 try 块外部声明，以便 finally 块访问
    try {
      LogService.instance.info('开始测试音乐API: ${apiConfig.name}');
      // 1. 创建一个临时的文件夹用来存放wav格式音乐
      tempDir = await getTemporaryDirectory();
      testSaveDir = Directory(p.join(tempDir.path, 'api_test_music_wav'));
      
      // 确保目录在测试前是干净的
      if (await testSaveDir.exists()) {
        await testSaveDir.delete(recursive: true);
        LogService.instance.info('已清理旧的临时音乐测试目录: ${testSaveDir.path}');
      }
      await testSaveDir.create(recursive: true);
      LogService.instance.info('已创建临时音乐测试目录: ${testSaveDir.path}');

      // 2. 发起一个非常简单的音乐生成请求
      final audioFilePath = await MusicService.instance.generateMusic(
        prompt: '独立民谣,忧郁,内省,渴望,独自漫步,咖啡馆',
        lyrics: '[verse]\n街灯微亮晚风轻抚\n影子拉长独自漫步\n旧外套裹着深深忧郁\n不知去向渴望何处\n[chorus]\n推开木门香气弥漫\n熟悉的角落陌生人看',
        apiConfig: apiConfig,
        saveDir: testSaveDir.path,
        outputFormat: 'wav', 
      );

      // 3. 检查结果：文件路径是否存在且指向一个真实文件
      if (audioFilePath != null && audioFilePath.isNotEmpty) {
        final File generatedFile = File(audioFilePath);
        if (await generatedFile.exists()) {
          LogService.instance.info('音乐文件成功生成并保存到: $audioFilePath');
          return TestResult(true, '测试成功: API成功生成并保存了 WAV 音频文件到: $audioFilePath');
        } else {
          LogService.instance.error('API声称成功，但音频文件未在指定路径找到: $audioFilePath');
          return TestResult(false, '测试失败: API调用成功，但音频文件未在指定路径找到。');
        }
      } else {
        LogService.instance.error('API调用成功，但未返回有效的音频文件路径。');
        return TestResult(false, '测试失败: API调用成功，但未返回有效的音频文件路径。');
      }
    } catch (e, s) {
      LogService.instance.error('音乐API测试失败', e, s);
      return TestResult(false, '测试失败: ${e.toString()}');
    } finally {
      // 4. 最后删除临时文件夹及其内容
      if (testSaveDir != null && await testSaveDir.exists()) {
        try {
          await testSaveDir.delete(recursive: true);
          LogService.instance.info('已删除临时音乐测试目录: ${testSaveDir.path}');
        } catch (e) {
          LogService.instance.error('删除临时音乐测试目录失败: ${testSaveDir.path}', e);
        }
      }
    }
  }
}