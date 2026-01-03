// lib/services/music_service/music_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../base/api_model.dart';
import '../../base/log/log_service.dart';

class MusicService {
  MusicService._();
  static final MusicService instance = MusicService._();

  final http.Client _client = http.Client();

  /// 生成音乐
  Future<String?> generateMusic({
    required String prompt,
    required String lyrics,
    required ApiModel apiConfig,
    required String saveDir,
    String outputFormat = 'wav',
  }) async {
    // 确保保存目录存在
    final directory = Directory(saveDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    String endpoint = apiConfig.url;
    if (!endpoint.endsWith('/music_generation')) {
      if (endpoint.endsWith('/')) {
        endpoint = '${endpoint}music_generation';
      } else {
        endpoint = '$endpoint/music_generation';
      }
    }

    final uri = Uri.parse(endpoint);
    
    final headers = {
      'Authorization': 'Bearer ${apiConfig.apiKey}',
      'Content-Type': 'application/json',
    };

    // --- 关键修改：请求 hex 格式数据，并指定 wav 格式 ---
    final body = jsonEncode({
      "model": apiConfig.model,
      "prompt": prompt,
      "lyrics": lyrics,
      "stream": false,
      "output_format": "hex", // 请求 hex 编码的音频数据
      "audio_setting": {
        "sample_rate": 44100, // 高质量采样率
        "bitrate": 256000,
        "format": outputFormat // 使用参数指定的格式 (如 "wav")
      }
    });

    LogService.instance.info('正在请求 Minimaxi 音乐生成: $endpoint');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 300)); // 音乐生成可能较慢，设置长超时

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // 检查业务状态码
        if (data['base_resp'] != null && data['base_resp']['status_code'] != 0) {
           final errorMsg = 'Minimaxi 业务错误: ${data['base_resp']['status_msg']} (Code: ${data['base_resp']['status_code']})';
           LogService.instance.error(errorMsg);
           throw Exception(errorMsg);
        }

        if (data['data'] != null && data['data']['audio'] != null) {
          final String hexAudioData = data['data']['audio'];
          
          // 将 hex 字符串转换为字节列表
          final List<int> audioBytes = _hexToBytes(hexAudioData);

          if (audioBytes.isEmpty) {
            throw Exception('响应中未包含有效的 hex 音频数据');
          }

          // 生成唯一的文件名并保存到指定目录
          final fileName = 'generated_music_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
          final filePath = p.join(saveDir, fileName); // 使用 path.join 跨平台拼接路径
          final file = File(filePath);
          await file.writeAsBytes(audioBytes); // 将字节写入文件
          
          LogService.instance.info('音乐已保存到: $filePath');
          return filePath; // 返回文件路径
        } else {
           throw Exception('响应中未包含音频数据 (data.audio)');
        }
      } else {
        final errorMsg = '音乐生成请求失败 [${response.statusCode}]: ${response.body}';
        LogService.instance.error(errorMsg);
        throw Exception(errorMsg);
      }
    } catch (e, s) {
      LogService.instance.error('Minimaxi 音乐生成异常', e, s);
      rethrow;
    }
  }

  /// 辅助函数：将 hex 字符串转换为 List<int> (字节数组)
  List<int> _hexToBytes(String hexString) {
    if (hexString.isEmpty) return [];
    final List<int> bytes = [];
    try {
      for (int i = 0; i < hexString.length; i += 2) {
        final String hexPair = hexString.substring(i, i + 2);
        bytes.add(int.parse(hexPair, radix: 16));
      }
    } catch (e) {
      LogService.instance.error('Hex字符串转换字节失败: $e');
      return [];
    }
    return bytes;
  }
}