// lib/services/task_manager/task_manager_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/bookshelf_entry.dart';
import '../cache_manager/cache_manager.dart';
import '../task_executor/illustration_generator_service.dart';
import '../task_executor/translation_generator_service.dart';

class CancellationToken {
  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  void cancel() => _isCanceled = true;
}

// 定义任务类型，用于区分要执行的任务
enum TaskType { illustration, translation }

class TaskManagerService {
  TaskManagerService._internal();
  static final TaskManagerService instance = TaskManagerService._internal();

  final ValueNotifier<List<BookshelfEntry>> tasksNotifier = ValueNotifier([]);
  final Map<String, CancellationToken> _cancellationTokens = {};
  
  final List<BookshelfEntry> _runningTasks = [];
  
  final int _maxConcurrentTasks = 1;

  Future<void> init() async {
    await _loadTasksFromCache();
    final entries = tasksNotifier.value;
    bool needsSave = false;
    for (var i = 0; i < entries.length; i++) {
      // 将所有正在运行或排队的任务在启动时都设置为“暂停”状态
      if (entries[i].status == TaskStatus.running || entries[i].status == TaskStatus.queued) {
        entries[i].status = TaskStatus.paused;
        needsSave = true;
      }
      // 对翻译任务也执行同样的操作
      if (entries[i].translationStatus == TaskStatus.running || entries[i].translationStatus == TaskStatus.queued) {
        entries[i].translationStatus = TaskStatus.paused;
        needsSave = true;
      }
    }
    if (needsSave) {
      tasksNotifier.value = List.from(entries);
      await _saveTasksToCache();
    }
  }
  
  // [新增方法]
  /// 重新从缓存加载任务列表，用于在外部数据源（如书架）更新后同步状态
  Future<void> reloadData() async {
    await _loadTasksFromCache();
  }

  void resumeAllTasks() {
    final entries = List<BookshelfEntry>.from(tasksNotifier.value);
    bool needsUpdate = false;
    for (var entry in entries) {
      // 将所有暂停的任务重新放入队列
      if (entry.status == TaskStatus.paused) {
        entry.status = TaskStatus.queued;
        needsUpdate = true;
      }
      if (entry.translationStatus == TaskStatus.paused) {
        entry.translationStatus = TaskStatus.queued;
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      tasksNotifier.value = entries;
      _saveTasksToCache();
    }
    
    // 开始处理队列
    processQueue();
  }

  Future<void> _loadTasksFromCache() async {
    try {
      tasksNotifier.value = await CacheManager().loadBookshelf();
    } catch (e) { print('从书架加载任务列表失败: $e'); tasksNotifier.value = []; }
  }

  Future<void> _saveTasksToCache() async {
    try {
      await CacheManager().saveBookshelf(tasksNotifier.value);
    } catch (e) { print('保存任务列表到书架失败: $e'); }
  }

  void _updateEntry(BookshelfEntry entry) {
    final entries = tasksNotifier.value;
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = entry;
      tasksNotifier.value = List.from(entries);
    } else {
      tasksNotifier.value = [...entries, entry];
    }
    _saveTasksToCache();
  }

  BookshelfEntry? getTaskEntry(String entryId) {
    try { return tasksNotifier.value.firstWhere((e) => e.id == entryId); } catch (e) { return null; }
  }
  
  void processQueue() {
    if (_runningTasks.length >= _maxConcurrentTasks) {
       print("已有任务正在运行，等待其完成后再处理下一个...");
      return;
    }
    
    BookshelfEntry? nextTaskEntry;
    TaskType? nextTaskType;

    try {
      // 优先查找插图任务
      nextTaskEntry = tasksNotifier.value.firstWhere((e) => e.status == TaskStatus.queued);
      nextTaskType = TaskType.illustration;
    } catch (e) {
      try {
        // 如果没有插图任务，再查找翻译任务
        nextTaskEntry = tasksNotifier.value.firstWhere((e) => e.translationStatus == TaskStatus.queued);
        nextTaskType = TaskType.translation;
      } catch (e) {
        return; // 两种类型的排队任务都没有
      }
    }
    
    _executeTask(nextTaskEntry, nextTaskType);
  }

  Future<void> _executeTask(BookshelfEntry entry, TaskType taskType) async {
    _runningTasks.add(entry);
    final token = CancellationToken();
    _cancellationTokens[entry.id] = token;

    // 根据任务类型更新状态
    if (taskType == TaskType.illustration) {
      _updateEntry(entry.copyWith(status: TaskStatus.running, clearErrorMessage: true));
    } else {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.running, clearTranslationErrorMessage: true));
    }

    final book = await CacheManager().loadBookDetail(entry.id);
    if (book == null) {
      final updatedEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: TaskStatus.failed, errorMessage: "找不到书籍详细数据缓存。")
        : entry.copyWith(translationStatus: TaskStatus.failed, translationErrorMessage: "找不到书籍详细数据缓存。");
      _updateEntry(updatedEntry);
      
      _runningTasks.removeWhere((e) => e.id == entry.id);
      _cancellationTokens.remove(entry.id);
      processQueue();
      return;
    }
    
    try {
      if (taskType == TaskType.illustration) {
        await IllustrationGeneratorService.instance.generateForBook(
          book,
          cancellationToken: token,
          onProgressUpdate: (progress, chunkStatus) async {
            final currentEntry = getTaskEntry(entry.id);
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

      final finalStatus = token.isCanceled ? TaskStatus.canceled : TaskStatus.completed;
      final finalEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: finalStatus)
        : entry.copyWith(translationStatus: finalStatus);
      _updateEntry(finalEntry);

    } catch (e) {
      print('任务执行失败: ${entry.id}, $e');
      final failedEntry = taskType == TaskType.illustration
        ? entry.copyWith(status: TaskStatus.failed, errorMessage: e.toString())
        : entry.copyWith(translationStatus: TaskStatus.failed, translationErrorMessage: e.toString());
      _updateEntry(failedEntry);
    } finally {
      _runningTasks.removeWhere((e) => e.id == entry.id);
      _cancellationTokens.remove(entry.id);
      await _saveTasksToCache();
      processQueue();
    }
  }

  void pauseTask(String entryId, TaskType taskType) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    if (taskType == TaskType.illustration && entry.status == TaskStatus.running) {
      _updateEntry(entry.copyWith(status: TaskStatus.paused));
    } 
    else if (taskType == TaskType.translation && entry.translationStatus == TaskStatus.running) {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.paused));
    }
  }

  void resumeTask(String entryId, TaskType taskType) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    // 单个任务的“继续”操作现在应该是将其状态改为排队中，然后让队列处理器来决定何时运行
    if (taskType == TaskType.illustration && entry.status == TaskStatus.paused) {
      _updateEntry(entry.copyWith(status: TaskStatus.queued));
      processQueue(); // 尝试处理队列
    } else if (taskType == TaskType.translation && entry.translationStatus == TaskStatus.paused) {
      _updateEntry(entry.copyWith(translationStatus: TaskStatus.queued));
      processQueue(); // 尝试处理队列
    }
  }

  void cancelTask(String entryId) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    
    // 取消正在运行的任务（无论类型）
    _cancellationTokens[entryId]?.cancel();

    // 将排队中的任务直接设置为取消
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
    }
  }
  
  void retryTask(String entryId) {
    final entry = getTaskEntry(entryId);
    if (entry == null) return;
    
    var updatedEntry = entry;
    bool changed = false;
    if (entry.status == TaskStatus.failed || entry.status == TaskStatus.canceled) {
       updatedEntry = updatedEntry.copyWith(status: TaskStatus.queued, clearErrorMessage: true);
       changed = true;
    }
    if (entry.translationStatus == TaskStatus.failed || entry.translationStatus == TaskStatus.canceled) {
       updatedEntry = updatedEntry.copyWith(translationStatus: TaskStatus.queued, clearTranslationErrorMessage: true);
       changed = true;
    }

    if (changed) {
      _updateEntry(updatedEntry);
      processQueue();
    }
  }

  void clearCompletedTasks() {
    final entries = tasksNotifier.value;
    bool changed = false;
    final updatedEntries = entries.map((entry) {
      var newEntry = entry;
      if (entry.status == TaskStatus.completed) {
        newEntry = newEntry.copyWith(status: TaskStatus.notStarted, taskChunks: []);
        changed = true;
      }
      if (entry.translationStatus == TaskStatus.completed) {
        newEntry = newEntry.copyWith(translationStatus: TaskStatus.notStarted, translationTaskChunks: []);
        changed = true;
      }
      return newEntry;
    }).toList();

    if(changed) {
      tasksNotifier.value = updatedEntries;
      _saveTasksToCache();
    }
  }
  
  void deleteTask(String entryId) {
    cancelTask(entryId); // 先尝试取消
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
    }
  }
}