// lib/ui/reader/game_book/dialogs/game_settings_ui.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';
import '../../../../base/config_service.dart'; // [新增] 引入配置服务

class GameSettingsUI {

  /// 显示设置面板
  static void showSettingsPanel(BuildContext context, GameManager gameManager) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SingleChildScrollView( 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text("系统设置", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
        
              ListTile(
                leading: const Icon(Icons.history_edu, color: Colors.amberAccent),
                title: const Text("历史记录", style: TextStyle(color: Colors.white)),
                subtitle: const Text("回顾过去的旅程与对话", style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showHistoryEventsPanel(context, gameManager);
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.today, color: Colors.greenAccent),
                title: const Text("今日日程", style: TextStyle(color: Colors.white)),
                subtitle: const Text("管理当前时间线的事件状态", style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showTodayEventsPanel(context, gameManager);
                },
              ),
              const Divider(color: Colors.white10, height: 1),
        
              // --- 媒体设置入口 ---
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.pinkAccent),
                title: const Text("媒体设置", style: TextStyle(color: Colors.white)),
                subtitle: const Text("背景音乐与音效控制", style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.settings, color: Colors.white30, size: 16),
                onTap: () {
                  Navigator.pop(context); 
                  _showMediaSettingsDialog(context); 
                },
              ),
              const Divider(color: Colors.white10, height: 1),
        
              ListTile(
                leading: const Icon(Icons.public, color: Colors.blueAccent),
                title: const Text("修改世界观 ", style: TextStyle(color: Colors.white)),
                subtitle: const Text("调整世界的底层逻辑与背景设定", style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.edit, color: Colors.white30, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showConfigEditor(context, gameManager, "世界观设定", "world_background");
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                title: const Text("修改故事指引", style: TextStyle(color: Colors.white)),
                subtitle: const Text("引导 AI 推进剧情的方向与风格", style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.edit, color: Colors.white30, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showConfigEditor(context, gameManager, "故事发展指引", "story_direction");
                },
              ),
              const SizedBox(height: 30),
              SizedBox(height: MediaQuery.of(context).padding.bottom), 
            ],
          ),
        );
      },
    );
  }

  /// 显示场景事件列表
  static void showSceneEventsSheet({
    required BuildContext context,
    required Map<String, dynamic> scene,
    required GameManager gameManager,
    required Function(Map<String, dynamic>) onPlayEvent,
  }) {
    final events = gameManager.getEventsForScene(scene);

    if (events.isEmpty) {
      if (scene['is_temporary'] == true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('场景【${scene['name']}】当前风平浪静。'), backgroundColor: Colors.grey.shade800, duration: const Duration(milliseconds: 800)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${scene['name']} 的遭遇', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final dialogues = (event['dialogues'] as List?) ?? [];
                    final preview = dialogues.isNotEmpty ? dialogues.last['message'] : '未知事件';
                    final status = event['status'] == 'playing' ? '进行中' : '突发事件';
                    
                    return ListTile(
                      leading: Icon(
                        event['status'] == 'playing' ? Icons.play_circle_fill : Icons.priority_high, 
                        color: event['status'] == 'playing' ? Colors.blueAccent : Colors.amber
                      ),
                      title: Text(status, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 14),
                      onTap: () {
                        Navigator.pop(context);
                        onPlayEvent(event);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- 内部私有方法 ---

  // --- 媒体设置弹窗逻辑 ---
  static void _showMediaSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        // 使用 StatefulBuilder 以便在 Dialog 内部刷新 Switch 状态
        return StatefulBuilder(
          builder: (context, setState) {
            final config = ConfigService();
            // 获取配置，默认值为 true
            final bool autoPlay = config.getSetting('game_bgm_autoplay', true);
            final bool loop = config.getSetting('game_bgm_loop', true);

            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text("媒体设置", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("背景音乐自动播放", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("进入场景时自动播放BGM", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    activeThumbColor: Colors.pinkAccent,
                    value: autoPlay,
                    onChanged: (value) async {
                      await config.modifySetting('game_bgm_autoplay', value);
                      setState(() {}); // 刷新 Dialog 状态
                    },
                  ),
                  const Divider(color: Colors.white10),
                  SwitchListTile(
                    title: const Text("背景音乐自动循环", style: TextStyle(color: Colors.white)),
                    activeThumbColor: Colors.pinkAccent,
                    value: loop,
                    onChanged: (value) async {
                      await config.modifySetting('game_bgm_loop', value);
                      setState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _showHistoryEventsPanel(BuildContext context, GameManager gameManager) {
    final history = gameManager.historyEvents;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('历史足迹 (${history.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: history.isEmpty 
                  ? const Center(child: Text("暂无历史记录", style: TextStyle(color: Colors.white30)))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: history.length,
                      separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final event = history[index];
                        final summary = event['summary'] ?? '无摘要';
                        final timeVal = event['game_time'];
                        final timeStr = timeVal is int ? 'Day $timeVal' : '$timeVal';
                        final scene = event['scene_name'] ?? '未知地点';

                        return ListTile(
                          title: Text(summary, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                                child: Text(timeStr, style: const TextStyle(color: Colors.amber, fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                              Text(scene, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          trailing: const Icon(Icons.remove_red_eye, color: Colors.white30, size: 18),
                          onTap: () => _showEventDetailLog(context, event, gameManager),
                        );
                      },
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showEventDetailLog(BuildContext context, Map<String, dynamic> event, GameManager gameManager) {
    final dialogues = (event['dialogues'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(event['summary'] ?? '事件回顾', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: dialogues.isEmpty 
            ? const Center(child: Text("无对话记录", style: TextStyle(color: Colors.white30)))
            : ListView.separated(
                itemCount: dialogues.length,
                separatorBuilder: (c, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final line = dialogues[index];
                  final name = line['name'] ?? '???';
                  final msg = line['message'] ?? '';
                  final isPlayer = name == gameManager.player['name'] || name == '玩家';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(
                        color: isPlayer ? Colors.blueAccent : Colors.amberAccent, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 12
                      )),
                      const SizedBox(height: 2),
                      Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  static void _showTodayEventsPanel(BuildContext context, GameManager gameManager) {
    final events = gameManager.todayEvents;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (context, scrollController) => Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('今日事件 (${events.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Text('左滑或点击操作', style: TextStyle(color: Colors.white30, fontSize: 12)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: events.isEmpty 
                      ? const Center(child: Text("今日无事发生", style: TextStyle(color: Colors.white30)))
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: events.length,
                          separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final event = events[index];
                            final status = event['status'] ?? 'pending';
                            final summary = event['summary'] ?? '未知事件';
                            final scene = event['scene_id'] ?? '未知区域';

                            Color statusColor;
                            IconData statusIcon;

                            switch(status) {
                              case 'completed':
                                statusColor = Colors.grey;
                                statusIcon = Icons.check_circle;
                                break;
                              case 'playing':
                                statusColor = Colors.blueAccent;
                                statusIcon = Icons.play_circle_fill;
                                break;
                              default: // pending
                                statusColor = Colors.amber;
                                statusIcon = Icons.hourglass_empty;
                            }

                            return ListTile(
                              leading: Icon(statusIcon, color: statusColor),
                              title: Text(summary, style: TextStyle(
                                color: status == 'completed' ? Colors.white38 : Colors.white,
                                decoration: status == 'completed' ? TextDecoration.lineThrough : null,
                              )),
                              subtitle: Text("地点: $scene", style: const TextStyle(color: Colors.white30, fontSize: 12)),
                              trailing: status == 'completed' 
                                ? IconButton(
                                    icon: const Icon(Icons.refresh, color: Colors.greenAccent),
                                    tooltip: "重新激活",
                                    onPressed: () async {
                                      await gameManager.reactivateEvent(event['id']);
                                      setSheetState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("事件已重置为待触发状态"), duration: Duration(milliseconds: 800)),
                                      );
                                    },
                                  )
                                : null,
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  static void _showConfigEditor(BuildContext context, GameManager gameManager, String title, String configKey) {
    final initialValue = gameManager.worldConfig[configKey]?.toString() ?? '';
    final TextEditingController controller = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("此设置将影响后续生成的事件与剧情走向。", style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  minLines: 5,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    hintText: "在此输入$title...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              final newValue = controller.text.trim();
              if (newValue != initialValue) {
                await gameManager.updateWorldSetting(configKey, newValue);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设置已保存"), backgroundColor: Colors.green));
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}