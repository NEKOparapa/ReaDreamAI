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
    String? lyrics,
    required ApiModel apiConfig,
    required String saveDir,
    String outputFormat = 'wav',
    bool? isInstrumental,
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

    // MiniMax 官方示例更推荐返回下载 URL，再单独拉取音频文件。
    final normalizedLyrics = lyrics?.trim();
    final useInstrumental =
        isInstrumental ??
        (normalizedLyrics == null || normalizedLyrics.isEmpty);

    final requestBody = <String, dynamic>{
      "model": apiConfig.model,
      "prompt": prompt,
      "is_instrumental": useInstrumental,
      "stream": false,
      "output_format": "url",
      "audio_setting": {
        "sample_rate": 44100, // 高质量采样率
        "bitrate": 256000,
        "format": outputFormat, // 使用参数指定的格式 (如 "wav")
      },
    };
    if (!useInstrumental &&
        normalizedLyrics != null &&
        normalizedLyrics.isNotEmpty) {
      requestBody["lyrics"] = normalizedLyrics;
    }

    final body = jsonEncode(requestBody);

    LogService.instance.info('正在请求 Minimaxi 音乐生成: $endpoint');

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(minutes: 10)); // 音乐生成可能较慢

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        // 检查业务状态码
        if (data['base_resp'] != null &&
            data['base_resp']['status_code'] != 0) {
          final errorMsg =
              'Minimaxi 业务错误: ${data['base_resp']['status_msg']} (Code: ${data['base_resp']['status_code']})';
          LogService.instance.error(errorMsg);
          throw Exception(errorMsg);
        }

        if (data['data'] != null && data['data']['audio'] != null) {
          final dynamic audioData = data['data']['audio'];
          final List<int> audioBytes = await _resolveAudioBytes(audioData);
          if (audioBytes.isEmpty) {
            throw Exception('响应中未包含可保存的音频数据');
          }

          final fileName =
              'generated_music_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
          final filePath = p.join(saveDir, fileName);
          final file = File(filePath);
          await file.writeAsBytes(audioBytes);

          LogService.instance.info('音乐已保存到: $filePath');
          return filePath;
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

  Future<List<int>> _resolveAudioBytes(dynamic audioData) async {
    if (audioData is! String || audioData.trim().isEmpty) {
      return [];
    }

    final normalized = audioData.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      LogService.instance.info('MiniMax 返回音频下载地址，开始下载文件...');
      final downloadResponse = await _client
          .get(Uri.parse(normalized))
          .timeout(const Duration(minutes: 3));
      if (downloadResponse.statusCode != 200) {
        throw Exception(
          '音频下载失败 [${downloadResponse.statusCode}]: ${downloadResponse.body}',
        );
      }
      return downloadResponse.bodyBytes;
    }

    final bytes = _hexToBytes(normalized);
    if (bytes.isNotEmpty) {
      return bytes;
    }

    throw Exception('无法识别 MiniMax 返回的音频数据格式');
  }

  /// 辅助函数：将 hex 字符串转换为字节数组
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
