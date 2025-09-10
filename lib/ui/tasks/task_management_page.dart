// lib/ui/tasks/task_management_page.dart

import 'package:flutter/material.dart';
import '../../models/bookshelf_entry.dart'; 
import '../../services/task_manager/task_manager_service.dart';

class TaskManagementPage extends StatefulWidget {
  const TaskManagementPage({super.key});

  @override
  State<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage> {
  final TaskManagerService _taskManager = TaskManagerService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务管理'),
        actions: [
          // [NEW] 新增一个“开始所有任务”的按钮
          ValueListenableBuilder<List<BookshelfEntry>>(
            valueListenable: _taskManager.tasksNotifier,
            builder: (context, entries, child) {
              // 仅当存在可开始的（暂停的）任务时才显示按钮
              final hasPausableTasks = entries.any((e) => e.status == TaskStatus.paused || e.translationStatus == TaskStatus.paused);
              if (hasPausableTasks) {
                return IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '开始/继续所有任务',
                  onPressed: () {
                    _taskManager.resumeAllTasks();
                  },
                );
              }
              return const SizedBox.shrink(); // 如果没有可开始的任务，则不显示按钮
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: '清除已完成的任务',
            onPressed: () {
              _taskManager.clearCompletedTasks();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<BookshelfEntry>>( 
        valueListenable: _taskManager.tasksNotifier,
        builder: (context, entries, child) {
          // 筛选出任何有活动任务的书籍
          final tasks = entries.where((e) => e.status != TaskStatus.notStarted || e.translationStatus != TaskStatus.notStarted).toList();

          if (tasks.isEmpty) {
            return const Center(
              child: Text(
                '当前没有任务',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }
          // 按更新时间倒序排列
          final sortedTasks = List<BookshelfEntry>.from(tasks)
            ..sort((a, b) {
                final aDate = a.updatedAt ?? a.translationUpdatedAt ?? a.createdAt ?? a.translationCreatedAt ?? DateTime(0);
                final bDate = b.updatedAt ?? b.translationUpdatedAt ?? b.createdAt ?? b.translationCreatedAt ?? DateTime(0);
                return bDate.compareTo(aDate);
            });
            
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: sortedTasks.length,
            itemBuilder: (context, index) {
              return _buildTaskItem(sortedTasks[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildTaskItem(BookshelfEntry task) { 
    bool hasIllustrationTask = task.status != TaskStatus.notStarted;
    bool hasTranslationTask = task.translationStatus != TaskStatus.notStarted;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (hasIllustrationTask)
              _buildSingleTaskInfo(
                task: task,
                type: TaskType.illustration,
                title: '插图生成',
                icon: Icons.auto_awesome,
                status: task.status,
                progress: task.illustrationProgress,
                errorMessage: task.errorMessage,
                updatedAt: task.updatedAt ?? task.createdAt,
              ),

            if (hasIllustrationTask && hasTranslationTask)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Divider(height: 1),
              ),

            if (hasTranslationTask)
              _buildSingleTaskInfo(
                task: task,
                type: TaskType.translation,
                title: '文本翻译',
                icon: Icons.translate,
                status: task.translationStatus,
                progress: task.translationProgress,
                errorMessage: task.translationErrorMessage,
                updatedAt: task.translationUpdatedAt ?? task.translationCreatedAt,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleTaskInfo({
    required BookshelfEntry task,
    required TaskType type,
    required String title,
    required IconData icon,
    required TaskStatus status,
    required double progress,
    required String? errorMessage,
    required DateTime? updatedAt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatusChip(status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '更新于: ${updatedAt?.toLocal().toString().substring(0, 19) ?? ""}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
        if (status == TaskStatus.running || status == TaskStatus.paused) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              status == TaskStatus.paused ? Colors.orange : Colors.blue
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${(progress * 100).toStringAsFixed(1)}%'),
          )
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            '错误: $errorMessage',
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: _buildActionButtons(task, type, status),
        ),
      ],
    );
  }

  Widget _buildStatusChip(TaskStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case TaskStatus.notStarted:
        color = Colors.grey;
        label = '未开始';
        icon = Icons.circle_outlined;
        break;
      case TaskStatus.queued:
        color = Colors.grey;
        label = '排队中';
        icon = Icons.queue;
        break;
      case TaskStatus.running:
        color = Colors.blue;
        label = '运行中';
        icon = Icons.directions_run;
        break;
      case TaskStatus.paused:
        color = Colors.orange;
        label = '已暂停';
        icon = Icons.pause_circle_filled;
        break;
      case TaskStatus.completed:
        color = Colors.green;
        label = '已完成';
        icon = Icons.check_circle;
        break;
      case TaskStatus.failed:
        color = Colors.red;
        label = '已失败';
        icon = Icons.error;
        break;
      case TaskStatus.canceled:
        color = Colors.black45;
        label = '已取消';
        icon = Icons.cancel;
        break;
    }
    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(label),
      backgroundColor: color,
      labelStyle: const TextStyle(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  List<Widget> _buildActionButtons(BookshelfEntry task, TaskType type, TaskStatus status) {
    List<Widget> buttons = [];
    switch (status) {
      case TaskStatus.running:
        buttons.add(_actionButton('暂停', Icons.pause, () => _taskManager.pauseTask(task.id, type)));
        buttons.add(_actionButton('取消', Icons.cancel, () => _taskManager.cancelTask(task.id)));
        break;
      case TaskStatus.paused:
        buttons.add(_actionButton('继续', Icons.play_arrow, () => _taskManager.resumeTask(task.id, type)));
        buttons.add(_actionButton('取消', Icons.cancel, () => _taskManager.cancelTask(task.id)));
        break;
      case TaskStatus.failed:
      case TaskStatus.canceled:
        buttons.add(_actionButton('重试', Icons.refresh, () => _taskManager.retryTask(task.id)));
        break;
      case TaskStatus.queued:
         buttons.add(_actionButton('取消', Icons.cancel, () => _taskManager.cancelTask(task.id)));
         break;
      case TaskStatus.completed:
      case TaskStatus.notStarted:
        break;
    }
    
    // 只有在整个书籍的所有任务都非运行时，才显示删除按钮
    if (task.status != TaskStatus.running && task.translationStatus != TaskStatus.running) {
       buttons.add(_actionButton('删除', Icons.delete_forever, () => _taskManager.deleteTask(task.id), isDestructive: true));
    }

    return buttons;
  }
  
  Widget _actionButton(String label, IconData icon, VoidCallback onPressed, {bool isDestructive = false}) {
    return TextButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: isDestructive ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}