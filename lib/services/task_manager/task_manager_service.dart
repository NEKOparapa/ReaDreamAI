// lib/services/task_manager/task_manager_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/bookshelf_entry.dart';
import '../cache_manager/cache_manager.dart';
import '../task_executor/illustration_generator_service.dart';
import '../task_executor/translation_generator_service.dart';
import '../../base/log/log_service.dart';

/// 任务取消令牌，用于通知正在运行的任务停止
class CancellationToken {
  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  void cancel() => _isCanceled = true;
}

/// 定义任务类型，区分插图生成和翻译
enum TaskType { illustration, translation }

/// 任务管理器服务 (单例)，负责调度和管理所有后台任务
class TaskManagerService {
  TaskManagerService._internal();
  static final TaskManagerService instance = TaskManagerService._internal();

  // 任务列表的响应式通知器
  final ValueNotifier<List<BookshelfEntry>> tasksNotifier = ValueNotifier([]);
  // 存储每个运行中任务的取消令牌
  final Map<String, CancellationToken> _cancellationTokens = {};
  
  // 当前正在运行的任务列表
  final List<BookshelfEntry> _runningTasks = [];
  
  // 最大并发任务数
  final int _maxConcurrentTasks = 1;

  /// 初始化任务管理器
  Future<void> init() async {
    // 1. 从缓存加载任务列表
    await _loadTasksFromCache();
    
    final entries = tasksNotifier.value;
    bool needsSave = false;

    // 2. 应用启动时，将所有“运行中”或“排队中”的任务重置为“暂停”状态，防止状态不同步
    for (var i = 0; i < entries.length; i++) {
      // 处理插图任务状态
      if (entries[i].status == TaskStatus.running || entries[i].status == TaskStatus.queued) {
        entries[i].status = TaskStatus.paused;
        needsSave = true;
      }
      // 处理翻译任务状态
      if (entries[i].translationStatus == TaskStatus.running || entries[i].translationStatus == TaskStatus.queued) {
        entries[i].translationStatus = TaskStatus.paused;
        needsSave = true;
      }
    }

    // 3. 如果状态有更新，则保存到缓存
    if (needsSave) {
      tasksNotifier.value = List.from(entries);
      await _saveTasksToCache();
      LogService.instance.info("任务管理器初始化完成，已将运行/排队任务重置为暂停。");
    }
  }
  
  /// 重新从缓存加载任务列表（例如：在外部更新了书架数据后同步）
  Future<void> reloadData() async {
    await _loadTasksFromCache();
  }

  /// 恢复所有暂停的任务（批量操作）
  void resumeAllTasks() {
    final entries = List<BookshelfEntry>.from(tasksNotifier.value);
    bool needsUpdate = false;
    for (var entry in entries) {
      // 将暂停的插图任务放回队列
      if (entry.status == TaskStatus.paused) {
        entry.status = TaskStatus.queued;
        needsUpdate = true;
      }
      // 将暂停的翻译任务放回队列
      if (entry.translationStatus == TaskStatus.paused) {
        entry.translationStatus = TaskStatus.queued;
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      tasksNotifier.value = entries;
      _saveTasksToCache();
      LogService.instance.info("已恢复所有暂停的任务到队列。");
    }
    
    // 启动队列处理
    processQueue();
  }

  /// 从缓存加载任务列表 (Bookshelf)
  Future<void> _loadTasksFromCache() async {
    try {
      tasksNotifier.value = await CacheManager().loadBookshelf();
    } catch (e) {
      // 使用日志服务记录错误
      LogService.instance.error('从书架加载任务列表失败', e);
      tasksNotifier.value = [];
    }
  }

  /// 将当前任务列表保存到缓存
  Future<void> _saveTasksToCache() async {
    try {
      await CacheManager().saveBookshelf(tasksNotifier.value);
    } catch (e) {
      // 使用日志服务记录错误
      LogService.instance.error('保存任务列表到书架失败', e);
    }
  }

  /// 更新任务列表中的单个条目并通知监听器
  void _updateEntry(BookshelfEntry entry) {
    final entries = tasksNotifier.value;
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = entry;
      tasksNotifier.value = List.from(entries);
    } else {
      tasksNotifier.value = [...entries, entry];
    }
    // 每次更新条目时尝试保存到缓存（可考虑优化为节流保存）
    _saveTasksToCache();
  }

  /// 根据 ID 获取任务条目
  BookshelfEntry? getTaskEntry(String entryId) {
    try {
      return tasksNotifier.value.firstWhere((e) => e.id == entryId);
    } catch (e) {
      return null;
    }
  }
  
  /// 处理任务队列，启动下一个排队任务
  void processQueue() {
    // 检查并发限制
    if (_runningTasks.length >= _maxConcurrentTasks) {
      // 使用日志服务记录信息
      LogService.instance.info("已有任务正在运行，等待其完成后再处理下一个...");
      return;
    }
    
    BookshelfEntry? nextTaskEntry;
    TaskType? nextTaskType;

    try {
      // 优先级 1: 查找排队的插图任务
      nextTaskEntry = tasksNotifier.value.firstWhere((e) => e.status == TaskStatus.queued);
      nextTaskType = TaskType.illustration;
    } catch (e) {
      try {
        // 优先级 2: 查找排队的翻译任务
        nextTaskEntry = tasksNotifier.value.firstWhere((e) => e.translationStatus == TaskStatus.queued);
        nextTaskType = TaskType.translation;
      } catch (e) {
        // 没有排队的任务
        return;
      }
    }
    
    // 执行找到的任务
    _executeTask(nextTaskEntry, nextTaskType);
  }

  /// 执行单个任务 (插图或翻译)
  Future<void> _executeTask(BookshelfEntry entry, TaskType taskType) async {
    _runningTasks.add(entry);
    final token = CancellationToken();
    _cancellationTokens[entry.id] = token;

    // 1. 更新任务状态为“运行中”
    if (taskType == TaskType.illustration) {
      _updateEntry(entry.copyWith(status: TaskStatus.running, clearErrorMessage: true));
    } else {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.running, clearTranslationErrorMessage: true));
    }

    LogService.instance.info("开始执行任务: ${entry.id}, 类型: ${taskType.name}");

    // 2. 加载书籍详情
    final book = await CacheManager().loadBookDetail(entry.id);
    if (book == null) {
      const errorMsg = "找不到书籍详细数据缓存。";
      final updatedEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: TaskStatus.failed, errorMessage: errorMsg)
        : entry.copyWith(translationStatus: TaskStatus.failed, translationErrorMessage: errorMsg);
      
      _updateEntry(updatedEntry);
      LogService.instance.warn("任务失败: ${entry.id}, 原因: $errorMsg");

      // 清理并继续处理队列
      _runningTasks.removeWhere((e) => e.id == entry.id);
      _cancellationTokens.remove(entry.id);
      processQueue();
      return;
    }
    
    // 3. 执行具体的生成服务
    try {
      if (taskType == TaskType.illustration) {
        await IllustrationGeneratorService.instance.generateForBook(
          book,
          cancellationToken: token,
          onProgressUpdate: (progress, chunkStatus) async {
            // 进度更新回调
            final currentEntry = getTaskEntry(entry.id);
            // 如果任务被暂停或不存在，则停止更新
            if (currentEntry == null || getTaskEntry(entry.id)?.status == TaskStatus.paused) return;
            
            final chunkIndex = currentEntry.taskChunks.indexWhere((c) => c.id == chunkStatus.id);
            if (chunkIndex != -1) {
               currentEntry.taskChunks[chunkIndex].status = chunkStatus.status;
               _updateEntry(currentEntry.copyWith(updatedAt: DateTime.now()));
            }
          },
          isPaused: () => getTaskEntry(entry.id)?.status == TaskStatus.paused,
        );
      } else { // 翻译任务
        await TranslationGeneratorService.instance.generateForBook(
          book,
          cancellationToken: token,
          onProgressUpdate: (progress, chunkStatus) async {
            final currentEntry = getTaskEntry(entry.id);
            if (currentEntry == null || getTaskEntry(entry.id)?.translationStatus == TaskStatus.paused) return;
            
            final chunkIndex = currentEntry.translationTaskChunks.indexWhere((c) => c.id == chunkStatus.id);
            if (chunkIndex != -1) {
               currentEntry.translationTaskChunks[chunkIndex].status = chunkStatus.status;
               _updateEntry(currentEntry.copyWith(translationUpdatedAt: DateTime.now()));
            }
          },
          isPaused: () => getTaskEntry(entry.id)?.translationStatus == TaskStatus.paused,
        );
      }

      // 4. 任务完成或取消
      final finalStatus = token.isCanceled ? TaskStatus.canceled : TaskStatus.completed;
      final finalEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: finalStatus)
        : entry.copyWith(translationStatus: finalStatus);
      _updateEntry(finalEntry);

      if (finalStatus == TaskStatus.completed) {
          LogService.instance.success("任务完成: ${entry.id}, 类型: ${taskType.name}");
      } else {
          LogService.instance.warn("任务已取消: ${entry.id}, 类型: ${taskType.name}");
      }

    } catch (e, stackTrace) {
      // 5. 任务执行出错
      // 使用日志服务记录错误和堆栈信息
      LogService.instance.error('任务执行失败: ${entry.id}', e, stackTrace);
      
      final failedEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: TaskStatus.failed, errorMessage: e.toString())
        : entry.copyWith(translationStatus: TaskStatus.failed, translationErrorMessage: e.toString());
      _updateEntry(failedEntry);
    } finally {
      // 6. 清理工作
      _runningTasks.removeWhere((e) => e.id == entry.id);
      _cancellationTokens.remove(entry.id);
      await _saveTasksToCache();
      // 继续处理下一个任务
      processQueue();
    }
  }

  /// 暂停指定任务
  void pauseTask(String entryId, TaskType taskType) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;

    if (taskType == TaskType.illustration && entry.status == TaskStatus.running) {
      _updateEntry(entry.copyWith(status: TaskStatus.paused));
      LogService.instance.info("插图任务已暂停: $entryId");
    } 
    else if (taskType == TaskType.translation && entry.translationStatus == TaskStatus.running) {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.paused));
      LogService.instance.info("翻译任务已暂停: $entryId");
    }
  }

  /// 恢复指定任务（将其置回队列）
  void resumeTask(String entryId, TaskType taskType) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;

    if (taskType == TaskType.illustration && entry.status == TaskStatus.paused) {
      _updateEntry(entry.copyWith(status: TaskStatus.queued));
      LogService.instance.info("插图任务已恢复到队列: $entryId");
      processQueue(); 
    } else if (taskType == TaskType.translation && entry.translationStatus == TaskStatus.paused) {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.queued));
      LogService.instance.info("翻译任务已恢复到队列: $entryId");
      processQueue();
    }
  }

  /// 取消指定任务
  void cancelTask(String entryId) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    
    // 1. 如果任务正在运行，发送取消信号
    _cancellationTokens[entryId]?.cancel();

    // 2. 如果任务在排队，直接修改状态为取消
    var updatedEntry = entry;
    bool changed = false;
    if (entry.status == TaskStatus.queued) {
       updatedEntry = updatedEntry.copyWith(status: TaskStatus.canceled);
       changed = true;
    }
    if (entry.translationStatus == TaskStatus.queued) {
       updatedEntry = updatedEntry.copyWith(translationStatus: TaskStatus.canceled);
       changed = true;
    }
    
    if (changed) {
      _updateEntry(updatedEntry);
      LogService.instance.info("已取消排队中的任务: $entryId");
    }
  }
  
  /// 重试失败或已取消的任务
  void retryTask(String entryId) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    
    var updatedEntry = entry;
    bool changed = false;

    // 重试插图任务
    if (entry.status == TaskStatus.failed || entry.status == TaskStatus.canceled) {
       updatedEntry = updatedEntry.copyWith(status: TaskStatus.queued, clearErrorMessage: true);
       changed = true;
    }
    // 重试翻译任务
    if (entry.translationStatus == TaskStatus.failed || entry.translationStatus == TaskStatus.canceled) {
       updatedEntry = updatedEntry.copyWith(translationStatus: TaskStatus.queued, clearTranslationErrorMessage: true);
       changed = true;
    }

    if (changed) {
      _updateEntry(updatedEntry);
      LogService.instance.info("任务已重置到队列进行重试: $entryId");
      processQueue();
    }
  }

  /// 清除所有已完成的任务记录（重置为未开始状态）
  void clearCompletedTasks() {
    final entries = tasksNotifier.value;
    bool changed = false;
    final updatedEntries = entries.map((entry) {
      var newEntry = entry;
      if (entry.status == TaskStatus.completed) {
        // 重置插图任务，清空分块数据
        newEntry = newEntry.copyWith(status: TaskStatus.notStarted, taskChunks: []);
        changed = true;
      }
      if (entry.translationStatus == TaskStatus.completed) {
        // 重置翻译任务，清空分块数据
        newEntry = newEntry.copyWith(translationStatus: TaskStatus.notStarted, translationTaskChunks: []);
        changed = true;
      }
      return newEntry;
    }).toList();

    if(changed) {
      tasksNotifier.value = updatedEntries;
      _saveTasksToCache();
      LogService.instance.info("已清除所有已完成的任务记录。");
    }
  }
  
  /// 删除任务（先取消，然后重置状态）
  void deleteTask(String entryId) {
    cancelTask(entryId); 
    final entry = getTaskEntry(entryId);
    if (entry != null) {
      _updateEntry(entry.copyWith(
        status: TaskStatus.notStarted,
        taskChunks: [],
        clearErrorMessage: true,
        translationStatus: TaskStatus.notStarted,
        translationTaskChunks: [],
        clearTranslationErrorMessage: true,
      ));
      LogService.instance.info("已删除任务 (重置状态): $entryId");
    }
  }
}