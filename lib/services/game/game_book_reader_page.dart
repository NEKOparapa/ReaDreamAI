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

  // --- 新增：设置面板逻辑 ---

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
              child: Text("设置", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
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
              title: const Text("修改故事发展", style: TextStyle(color: Colors.white)),
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

  void _showConfigEditor(String title, String configKey) {
    // 读取当前值，如果为空则为空字符串
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
                  maxLines: null, // 允许无限换行
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              final newValue = controller.text.trim();
              if (newValue != initialValue) {
                await _gameManager.updateWorldSetting(configKey, newValue);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("设置已保存，将在下次回合结算或事件生成时生效。"),
                      backgroundColor: Colors.green,
                    )
                  );
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  // --- 现有逻辑 ---

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
            content: SingleChildScrollView(
              child: Text(summary, style: const TextStyle(color: Colors.white70))
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('新的一天'))
            ],
          ),
        );
        setState(() {}); // 刷新 UI
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
        SnackBar(
          content: Text('场景【${scene['name']}】当前风平浪静。'),
          backgroundColor: Colors.grey.shade800,
          duration: const Duration(milliseconds: 800)
        ),
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
                    final preview = dialogues.isNotEmpty ? dialogues.last['message'] : '未知事件'; // 显示最后一句或摘要
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
    // 调用 Manager 的 startEvent 标记状态
    await _gameManager.startEvent(event);
    setState(() {
      _currentPlayingEvent = event;
    });
  }

  Future<void> _onEventFinished() async {
    if (mounted) {
      setState(() {
        _currentPlayingEvent = null;
      });
    }
  }

  Future<void> _onEventExit() async {
    // 退出时不自动完成，只是关闭 UI，进度已经在 Overlay 中保存
    if (mounted) {
      setState(() {
        _currentPlayingEvent = null;
      });
    }
  }

  // --- 信息展示逻辑 ---

  void _showPlayerDetail() {
    final player = _gameManager.player;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.blueGrey.shade800,
                            child: Text(
                              player['name']?.isNotEmpty == true ? player['name'][0] : 'P',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(player['name'] ?? '未命名主角', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          Text(player['identity'] ?? '冒险者', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildInfoSection('当前状态', player['status'] ?? '正常', icon: Icons.favorite),
                    _buildInfoSection('外貌描述', player['appearance'] ?? '无', icon: Icons.face),
                    const Divider(color: Colors.white12, height: 32),
                    const Text('背包与装备', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildInfoTile('装备', player['equipment'], Icons.shield),
                    _buildInfoTile('背包', player['backpack'], Icons.backpack),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 修改后的 AI 角色列表展示 ---
  void _showAiCharacterList() {
    final chars = _gameManager.aiCharacters;
    
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
                child: Text('登场角色 (${chars.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: chars.isEmpty 
                  ? const Center(child: Text("暂无其他角色", style: TextStyle(color: Colors.white30)))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: chars.length,
                      separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final char = chars[index];
                        final memories = (char['memory'] as List?) ?? [];
                        // 倒序显示记忆，最新的在上面
                        final reversedMemories = memories.reversed.toList();

                        return Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade900.withOpacity(0.5),
                              child: Text(char['name']?[0] ?? '?', style: const TextStyle(color: Colors.purpleAccent)),
                            ),
                            title: Text(char['name'] ?? '???', style: const TextStyle(color: Colors.white)),
                            subtitle: Text(char['status'] ?? '未知状态', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                color: Colors.black12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    // 基础属性
                                    if (char['identity'] != null) _buildAttributeRow('身份', char['identity']),
                                    if (char['personality'] != null) _buildAttributeRow('性格', char['personality']),
                                    
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: Divider(color: Colors.white10),
                                    ),
                                    
                                    // 记忆列表
                                    Row(
                                      children: [
                                        const Icon(Icons.psychology, size: 16, color: Colors.purpleAccent),
                                        const SizedBox(width: 8),
                                        Text('记忆档案 (${memories.length})', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    
                                    if (reversedMemories.isEmpty)
                                      const Text("暂无记忆数据", style: TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic))
                                    else
                                      ...reversedMemories.map((mem) {
                                        final timeVal = mem['time'];
                                        // 格式化时间，如果是 int 则显示 Day X，兼容旧数据 String
                                        final timeStr = timeVal is int ? 'Day $timeVal' : '$timeVal';
                                        final content = mem['content'] ?? '';

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border(left: BorderSide(color: Colors.purple.withOpacity(0.4), width: 3)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                                                child: Text(timeStr, style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(content, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                  ],
                                ),
                              )
                            ],
                          ),
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
  
  // 辅助构建属性行
  Widget _buildAttributeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label：', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content, {required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: Colors.blueAccent.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(content.isEmpty ? '暂无' : content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
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
          Icon(icon, color: Colors.white30, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 2),
                Text(text.isEmpty ? '空' : text, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                // 显示总天数
                Text("第 $week 周", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                // 显示周 + 天
                Text("DAY $dayOfWeek", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                if (eventStats['total']! > 0)
                  Text("${eventStats['total']} 个事件待触发", style: TextStyle(color: Colors.amber.withOpacity(0.7), fontSize: 10)),
              ],
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.groups, color: Colors.purpleAccent), onPressed: _showAiCharacterList), 
              IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: _showSettingsPanel),
            ]),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), offset: const Offset(0, -2), blurRadius: 10)]),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _showPlayerDetail, 
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 22, backgroundColor: Colors.blueGrey.shade800, child: Text(player['name']?.isNotEmpty == true ? player['name'][0] : 'P', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(player['name'] ?? 'Player', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text(player['status'] ?? '正常', style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white10),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
            ElevatedButton.icon(onPressed: _isSettling ? null : () => _triggerTurnSettlement(false), icon: const Icon(Icons.bedtime, size: 18), label: const Text("结束今天"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)))),
          ],
        ),
      ),
    );
  }
}