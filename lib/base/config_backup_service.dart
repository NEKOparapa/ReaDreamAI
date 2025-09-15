// lib/base/config_backup_service.dart

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../base/config_service.dart';

/// 服务类，用于处理应用配置的导入和导出
class ConfigBackupService {
  final ConfigService _configService = ConfigService();

  /// 导出所有应用数据到一个ZIP压缩文件
  ///
  /// 这包括 config.json, BookProjectsCache, character_images 等所有数据。
  /// 返回操作是否成功。
  Future<bool> exportConfiguration() async {
    try {
      // 1. 获取源目录，即整个应用数据目录
      final sourceDir = Directory(_configService.getAppDirectoryPath());
      if (!await sourceDir.exists()) {
        print("备份源目录不存在: ${sourceDir.path}");
        return false;
      }

      // 2. 弹出文件保存对话框，让用户选择保存位置和文件名
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择备份文件保存位置',
        fileName: 'app_backup_$timestamp.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      // 如果用户取消了选择，则返回 false
      if (outputFile == null) {
        return false;
      }

      // 3. 使用 archive 库创建并写入ZIP文件
      final encoder = ZipFileEncoder();
      encoder.create(outputFile);
      // 递归地将目录内容添加到压缩包中，不包含顶层目录本身
      encoder.addDirectory(sourceDir, includeDirName: false);
      encoder.close();

      print('配置已成功导出到: $outputFile');
      return true;

    } catch (e) {
      print('导出配置时发生错误: $e');
      return false;
    }
  }

  /// 从用户选择的ZIP压缩文件导入应用数据
  ///
  /// **警告**: 此操作会删除现有的所有数据，并且在成功后需要重启应用。
  /// 返回操作是否成功。
  Future<bool> importConfiguration() async {
    try {
      // 1. 弹出文件选择对话框，让用户选择一个备份文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: '选择要导入的备份文件',
      );

      // 如果用户取消了选择，则返回 false
      if (result == null || result.files.single.path == null) {
        return false;
      }

      final inputFile = File(result.files.single.path!);
      final appSupportDir = Directory(_configService.getAppDirectoryPath());

      // 2. 在执行覆盖操作前，删除现有的数据目录
      if (await appSupportDir.exists()) {
        await appSupportDir.delete(recursive: true);
      }
      // 3. 重新创建空的目录
      await appSupportDir.create(recursive: true);

      // 4. 读取ZIP文件并解压到应用数据目录
      final inputStream = InputFileStream(inputFile.path);
      final archive = ZipDecoder().decodeBuffer(inputStream);

      for (final file in archive) {
        final filename = p.join(appSupportDir.path, file.name);
        if (file.isFile) {
          // 确保文件所在的目录存在
          final parentDir = Directory(p.dirname(filename));
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          final outputStream = OutputFileStream(filename);
          file.writeContent(outputStream);
          await outputStream.close();
        } else {
          await Directory(filename).create(recursive: true);
        }
      }
      await inputStream.close();

      print('配置已成功导入');
      return true;

    } catch (e) {
      print('导入配置时发生错误: $e');
      return false;
    }
  }
}