// lib/ui/game/game_book_reader_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/bookshelf_entry.dart';
import 'game_manager.dart';
import 'galgame_player_overlay.dart';

class GameBookReaderPage extends StatefulWidget {
  final BookshelfEntry entry;
  const GameBookReaderPage({super.key, required this.entry});

  @override
  State<GameBookReaderPage> createState() => _GameBookReaderPageState();
}

class _GameBookReaderPageState extends State<GameBookReaderPage> {
  late GameManager _gameManager;
  bool _isLoading = true;
  bool _isSettling = false;

  Map<String, dynamic>? _currentPlayingEvent;

  @override
  void initState() {
    super.initState();
    _gameManager = GameManager(widget.entry);
    _initGame();
  }

  Future<void> _initGame() async {
    await _gameManager.loadGameData();
    if (mounted) setState(() => _isLoading = false);
  }

  // --- 逻辑区 ---

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Column(
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
                _showHistoryEventsPanel();
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
                _showTodayEventsPanel();
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
                _showConfigEditor("世界观设定", "world_background");
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
                _showConfigEditor("故事发展指引", "destiny_ai");
              },
            ),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  void _showHistoryEventsPanel() {
    final history = _gameManager.historyEvents;

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
                          onTap: () => _showEventDetailLog(event),
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

  void _showEventDetailLog(Map<String, dynamic> event) {
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
                  final isPlayer = name == _gameManager.player['name'] || name == '玩家';

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

  void _showTodayEventsPanel() {
    setState(() {}); 
    final events = _gameManager.todayEvents;

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
                                      await _gameManager.reactivateEvent(event['id']);
                                      setSheetState(() {});
                                      if (mounted) this.setState(() {}); 
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

  void _showConfigEditor(String title, String configKey) {
    final initialValue = _gameManager.worldConfig[configKey]?.toString() ?? '';
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
                await _gameManager.updateWorldSetting(configKey, newValue);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设置已保存"), backgroundColor: Colors.green));
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _triggerTurnSettlement(bool isNextWeek) async {
    setState(() => _isSettling = true);
    try {
      final summary = await _gameManager.processTurnSettlement(isNextWeek: isNextWeek);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: const Text('时之流逝', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(child: Text(summary, style: const TextStyle(color: Colors.white70))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('新的一天'))
            ],
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误: $e')));
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  void _onSceneTap(Map<String, dynamic> scene) {
    final events = _gameManager.getEventsForScene(scene);

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
                        _playEvent(event);
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

  void _playEvent(Map<String, dynamic> event) async {
    await _gameManager.startEvent(event);
    setState(() {
      _currentPlayingEvent = event;
    });
  }

  Future<void> _onEventFinished() async {
    if (mounted) setState(() => _currentPlayingEvent = null);
  }

  Future<void> _onEventExit() async {
    if (mounted) setState(() => _currentPlayingEvent = null);
  }


  // 1. 玩家详情 (可编辑)
  void _showPlayerDetail() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlayerSheet(gameManager: _gameManager),
    );
  }

  // 2. AI 角色列表 (详细)
  void _showAiCharacterList() {
    final chars = _gameManager.aiCharacters;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515), // 更深色的背景
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    const Icon(Icons.hub, color: Colors.purpleAccent),
                    const SizedBox(width: 8),
                    Text('角色列表 (${chars.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
              Expanded(
                child: chars.isEmpty 
                  ? const Center(child: Text("暂无角色", style: TextStyle(color: Colors.white30)))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: chars.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildAiCharacterCard(chars[index]);
                      },
                    ),
              ),
            ],
          ),
        );
      },
    );
  }


  // 构建单个 AI 卡片
  Widget _buildAiCharacterCard(Map<String, dynamic> char) {
    final memories = (char['memory'] as List?) ?? [];
    final reversedMemories = memories.reversed.take(5).toList(); 

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.3), width: 1),
        boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.purpleAccent, width: 2),
              // 如果没有图片，用首字代替
              color: Colors.black38, 
            ),
            child: Center(child: Text(char['name']?[0] ?? '?', style: const TextStyle(color: Colors.purpleAccent, fontSize: 20, fontWeight: FontWeight.bold))),
          ),
          title: Text(char['name'] ?? '???', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  if (char['identity'] != null) 
                    Flexible(
                      child: _buildTag(char['identity'], Colors.blueGrey),
                    ),
                  
                  if (char['identity'] != null && char['status'] != null)
                    const SizedBox(width: 6),
                  
                  if (char['status'] != null)
                    Flexible(
                      flex: 2, // 状态通常更重要或更长，给多一点空间
                      child: _buildTag(char['status'], Colors.green.withOpacity(0.8)),
                    ),
                ],
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CHAR. DATA", style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // 在详情里显示完整信息，不用担心长度
                  _buildDetailRow("身份", char['identity'] ?? '未知'),
                  _buildDetailRow("状态", char['status'] ?? '未知'), 
                  _buildDetailRow("性格", char['personality'] ?? '不明'),
                  _buildDetailRow("外貌", char['appearance'] ?? '模糊不清'),
                  _buildDetailRow("当前位置", char['location'] ?? '未知区域'),
                  
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("MEMORY LOG", style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                      Text("${memories.length} recs", style: const TextStyle(color: Colors.purpleAccent, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (reversedMemories.isEmpty)
                    const Text("无数据记录...", style: TextStyle(color: Colors.white24, fontStyle: FontStyle.italic, fontSize: 12))
                  else
                    ...reversedMemories.map((mem) {
                      final timeStr = mem['time'] is int ? 'DAY ${mem['time']}' : '${mem['time']}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(timeStr, style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontFamily: 'Monospace')),
                            const SizedBox(width: 8),
                            Expanded(child: Text(mem['content'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3))),
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建标签
  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2), 
        borderRadius: BorderRadius.circular(4), 
        border: Border.all(color: color.withOpacity(0.5))
      ),
      child: Text(
        text, 
        style: TextStyle(color: color, fontSize: 10),
        maxLines: 1, // 强制单行
        overflow: TextOverflow.ellipsis, // 超出显示省略号
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  // --- 主 UI 构建 ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator()));

    return WillPopScope(
      onWillPop: () async {
        if (_currentPlayingEvent != null) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('退出事件？', style: TextStyle(color: Colors.white)),
              content: const Text('确保已保存进度。未保存的进度将会丢失。', style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
              ],
            ),
          );
          if (shouldExit == true) {
            await _onEventExit();
            return true;
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildWorldMap()),
                _buildBottomControl(),
              ],
            ),
            if (_isSettling)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 20), Text("世界线变动中...", style: TextStyle(color: Colors.white, letterSpacing: 2))])),
              ),
            if (_currentPlayingEvent != null)
              GalgamePlayerOverlay(
                event: _currentPlayingEvent!,
                playerName: _gameManager.player['name'] ?? 'Player',
                gameManager: _gameManager,
                onFinished: _onEventFinished,
                onExit: _onEventExit,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final week = _gameManager.currentWeek;
    final dayOfWeek = _gameManager.currentDayOfWeek;
    final eventStats = _gameManager.getEventStats();

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
            Column(
              children: [
                Text("第 $week 周", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text("DAY $dayOfWeek", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Monospace')),
                if (eventStats['total']! > 0)
                  Text("${eventStats['total']} 事件待发生", style: TextStyle(color: Colors.amber.withOpacity(0.7), fontSize: 10)),
              ],
            ),
            IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: _showSettingsPanel),
          ],
        ),
      ),
    );
  }

  Widget _buildWorldMap() {
    final scenes = _gameManager.scenes;
    if (scenes.isEmpty) return const Center(child: Text("虚空世界", style: TextStyle(color: Colors.white24)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 12, runSpacing: 12, children: scenes.map((scene) => _buildSceneNode(scene)).toList()),
    );
  }

  Widget _buildSceneNode(Map<String, dynamic> scene) {
    final events = _gameManager.getEventsForScene(scene);
    final hasEvent = events.isNotEmpty;
    final isPlaying = events.any((e) => e['status'] == 'playing');
    final itemWidth = (MediaQuery.of(context).size.width - 44) / 2;
    final isTemporary = scene['is_temporary'] == true;

    Color borderColor = Colors.white10;
    if (hasEvent) {
      if (isPlaying) {
        borderColor = Colors.blueAccent.withOpacity(0.6);
      } else if (isTemporary) {
        borderColor = Colors.cyan.withOpacity(0.6);
      } else {
        borderColor = Colors.amber.withOpacity(0.6);
      }
    }

    return GestureDetector(
      onTap: () => _onSceneTap(scene),
      child: Container(
        width: itemWidth,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          gradient: hasEvent 
            ? LinearGradient(
                begin: Alignment.topLeft, 
                end: Alignment.bottomRight, 
                colors: [
                  const Color(0xFF252525), 
                  isPlaying ? Colors.blue.withOpacity(0.15) : (isTemporary ? Colors.cyan.withOpacity(0.15) : Colors.amber.withOpacity(0.1))
                ]
              ) 
            : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasEvent ? (isPlaying ? Icons.play_circle_filled : (isTemporary ? Icons.crisis_alert : Icons.location_on)) : Icons.location_on_outlined, 
                    color: hasEvent ? (isPlaying ? Colors.blueAccent : (isTemporary ? Colors.cyanAccent : Colors.amber)) : Colors.white24
                  ),
                  const SizedBox(height: 8),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(scene['name'] ?? 'Unknown', style: TextStyle(color: hasEvent ? Colors.white : Colors.white70, fontWeight: hasEvent ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                  if (hasEvent) Text('${events.length} 个事件', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                ],
              ),
            ),
            if (isTemporary)
               Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.cyan.shade900, borderRadius: BorderRadius.circular(4)), child: const Text('临时', style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControl() {
    final player = _gameManager.player;
    final aiCount = _gameManager.aiCharacters.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), offset: const Offset(0, -4), blurRadius: 16)],
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 玩家按钮
          _buildGameButton(
            label: player['name'] ?? 'Player',
            subLabel: 'Your status',
            icon: Icons.face,
            color: Colors.cyanAccent,
            onTap: _showPlayerDetail,
          ),
          
          const SizedBox(width: 12),

          // 2. AI 同伴按钮
          _buildGameButton(
            label: '同伴',
            subLabel: 'Link: $aiCount',
            icon: Icons.groups,
            color: Colors.purpleAccent,
            onTap: _showAiCharacterList,
          ),

          const Spacer(),

          // 3. 结算按钮
          InkWell(
            onTap: _isSettling ? null : () => _triggerTurnSettlement(false),
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.white10, Colors.white.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bedtime, size: 18, color: Colors.white70),
                  SizedBox(width: 8),
                  Text("休整", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameButton({required String label, required String subLabel, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
                Text(subLabel, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontFamily: 'Monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- 组件：玩家信息编辑页 ---
class _PlayerSheet extends StatefulWidget {
  final GameManager gameManager;
  const _PlayerSheet({required this.gameManager});

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _identityCtrl;
  late TextEditingController _appearanceCtrl;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final p = widget.gameManager.player;
    _nameCtrl = TextEditingController(text: p['name'] ?? '');
    _identityCtrl = TextEditingController(text: p['identity'] ?? '');
    _appearanceCtrl = TextEditingController(text: p['appearance'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identityCtrl.dispose();
    _appearanceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final newMap = {
      'name': _nameCtrl.text.trim(),
      'identity': _identityCtrl.text.trim(),
      'appearance': _appearanceCtrl.text.trim(),
    };
    widget.gameManager.updatePlayerProfile(newMap);
    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("档案已更新"), backgroundColor: Colors.cyan, duration: Duration(milliseconds: 800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.gameManager.player; 

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("个人终端", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(_isEditing ? Icons.save : Icons.edit, color: _isEditing ? Colors.greenAccent : Colors.cyanAccent),
                    onPressed: () {
                      if (_isEditing) {
                        _save();
                      } else {
                        setState(() => _isEditing = true);
                      }
                    },
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.cyan.shade900.withOpacity(0.5),
                          child: Text(
                            player['name']?.isNotEmpty == true ? player['name'][0] : 'P',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                          ),
                        ),
                        if (_isEditing)
                          Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 14, color: Colors.black))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionTitle("基础档案"),
                  const SizedBox(height: 12),
                  _buildEditableField("姓名", _nameCtrl, icon: Icons.badge),
                  const SizedBox(height: 12),
                  _buildEditableField("身份", _identityCtrl, icon: Icons.work),
                  const SizedBox(height: 12),
                  _buildEditableField("外貌特征", _appearanceCtrl, icon: Icons.face, maxLines: 3),
                  
                  const Divider(color: Colors.white12, height: 40),

                  _buildSectionTitle("物资与状态"),
                  const SizedBox(height: 12),
                  _buildInfoTile('装备', player['equipment'], Icons.shield),
                  _buildInfoTile('背包', player['backpack'], Icons.backpack),
                  _buildInfoTile('当前状态', player['status'], Icons.monitor_heart),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(color: Colors.cyanAccent.withOpacity(0.7), fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.bold));
  }

  Widget _buildEditableField(String label, TextEditingController controller, {required IconData icon, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: _isEditing ? Border.all(color: Colors.cyanAccent.withOpacity(0.3)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white38),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                const SizedBox(height: 4),
                _isEditing
                    ? TextField(
                        controller: controller,
                        maxLines: maxLines,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        controller.text.isEmpty ? '未填写' : controller.text,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        maxLines: maxLines,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, dynamic value, IconData icon) {
    final text = value?.toString() ?? '空';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white54, size: 18)
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 4),
                Text(text.isEmpty ? '空' : text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}