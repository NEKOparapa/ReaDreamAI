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

  // 当前正在触发的事件
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
            content: Text(summary, style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('新的一天')
              )
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('场景【${scene['name']}】当前风平浪静。'),
          backgroundColor: Colors.grey.shade800,
          duration: const Duration(milliseconds: 800)
        ),
      );
      return;
    }

    // 弹出底部菜单选择事件
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
              Text(
                '${scene['name']} 的遭遇', 
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final dialogues = (event['dialogues'] as List?) ?? [];
                    final preview = dialogues.isNotEmpty ? dialogues.first['message'] : '未知事件';
                    
                    return ListTile(
                      leading: const Icon(Icons.priority_high, color: Colors.amber),
                      title: const Text('突发事件', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        preview, 
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis, 
                        style: const TextStyle(color: Colors.white54)
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 14),
                      onTap: () {
                        Navigator.pop(context); // 关闭 Sheet
                        _playEvent(event); // 开始播放
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

  void _playEvent(Map<String, dynamic> event) {
    setState(() {
      _currentPlayingEvent = event;
    });
  }

  Future<void> _onEventFinished() async {
    if (_currentPlayingEvent != null) {
      // 1. 从数据中移除该事件
      await _gameManager.removeEvent(_currentPlayingEvent!);
      
      // 2. 退出播放模式
      if (mounted) {
        setState(() {
          _currentPlayingEvent = null;
        });
      }
    }
  }

  // --- 详情显示逻辑 ---

  // 构建详情行
  Widget _buildDetailRow(String label, dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value.toString(),
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // 显示玩家详情
  void _showPlayerDetail() {
    final player = _gameManager.player;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.account_circle, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  player['name'] ?? '玩家信息',
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('身份', player['identity']),
                  _buildDetailRow('状态', player['status']),
                  const Divider(color: Colors.white12, height: 20),
                  _buildDetailRow('外貌', player['appearance']),
                  const Divider(color: Colors.white12, height: 20),
                  _buildDetailRow('装备', player['equipment']),
                  _buildDetailRow('背包', player['backpack']),
                ],
              ),
            ),
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
  }

  // 显示 AI 角色详情
  void _showAiCharacterDetail(Map<String, dynamic> char) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.person, color: Colors.purpleAccent.shade100),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  char['name'] ?? '角色详情',
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('身份', char['identity']),
                  _buildDetailRow('状态', char['status']),
                  const Divider(color: Colors.white12, height: 20),
                  _buildDetailRow('性格', char['personality']),
                  _buildDetailRow('动机', char['motivation']),
                  _buildDetailRow('外貌', char['appearance']),
                  const Divider(color: Colors.white12, height: 20),
                  _buildDetailRow('装备', char['equipment']),
                  _buildDetailRow('背包', char['backpack']),
                  if (char['other'] != null && char['other'].toString().isNotEmpty)
                    _buildDetailRow('其他', char['other']),
                ],
              ),
            ),
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
  }

  void _showAiCharacterList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final aiChars = _gameManager.aiCharacters;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10))
              ),
              child: const Center(child: Text("AI 角色动态", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
            ),
            Expanded(
              child: aiChars.isEmpty 
              ? const Center(child: Text("暂无 AI 角色", style: TextStyle(color: Colors.white24)))
              : ListView.separated(
                  itemCount: aiChars.length,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final char = aiChars[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.withOpacity(0.2),
                        child: Text((char['name']?[0] ?? '?'), style: const TextStyle(color: Colors.purpleAccent)),
                      ),
                      title: Text(char['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(char['identity'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          Text("状态: ${char['status'] ?? '未知'}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.info_outline, color: Colors.white70),
                        tooltip: '查看详情',
                        onPressed: () => _showAiCharacterDetail(char),
                      ),
                    );
                  },
                ),
            ),
          ],
        );
      },
    );
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator())
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_currentPlayingEvent != null) return false;
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(
          children: [
            // 1. 底层：地图与状态
            Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildWorldMap()),
                _buildBottomControl(),
              ],
            ),

            // 2. 中间层：Loading 遮罩
            if (_isSettling)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text("世界线变动中...", style: TextStyle(color: Colors.white, letterSpacing: 2)),
                    ],
                  ),
                ),
              ),

            // 3. 顶层：Galgame 播放器
            if (_currentPlayingEvent != null)
              GalgamePlayerOverlay(
                event: _currentPlayingEvent!,
                playerName: _gameManager.player['name'] ?? 'Player',
                onFinished: _onEventFinished,
              ),
          ],
        ),
      ),
    );
  }

  // 右上角按钮
  Widget _buildTopBar() {
    final day = _gameManager.gameState['day'] ?? 1;
    final week = _gameManager.gameState['week'] ?? 1;
    
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左上角：返回
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
            
            // 中间：时间信息
            Column(
              children: [
                Text("第 $week 周", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text("DAY $day", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            
            // 右上角区域：功能按钮组
            Row(
              mainAxisSize: MainAxisSize.min, // 紧凑排列
              children: [
                // AI 角色列表按钮
                IconButton(
                  tooltip: 'AI 角色列表',
                  icon: const Icon(Icons.groups, color: Colors.purpleAccent),
                  onPressed: _showAiCharacterList,
                ),
                // 设置按钮
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                  onPressed: () {
                    // TODO: 设置功能
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorldMap() {
    final scenes = _gameManager.scenes;
    if (scenes.isEmpty) {
      return const Center(child: Text("虚空世界", style: TextStyle(color: Colors.white24)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: scenes.map((scene) => _buildSceneNode(scene)).toList(),
      ),
    );
  }

  Widget _buildSceneNode(Map<String, dynamic> scene) {
    final events = _gameManager.getEventsForScene(scene);
    final hasEvent = events.isNotEmpty;
    // 简单的网格计算，每行两个
    final itemWidth = (MediaQuery.of(context).size.width - 44) / 2;

    return GestureDetector(
      onTap: () => _onSceneTap(scene),
      child: Container(
        width: itemWidth,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: hasEvent 
            ? Border.all(color: Colors.amber.withOpacity(0.6), width: 1.5)
            : Border.all(color: Colors.white10),
          gradient: hasEvent ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF252525), Colors.amber.withOpacity(0.1)]
          ) : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasEvent ? Icons.location_on : Icons.location_on_outlined, 
                    color: hasEvent ? Colors.amber : Colors.white24
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scene['name'] ?? 'Unknown',
                    style: TextStyle(
                      color: hasEvent ? Colors.white : Colors.white70,
                      fontWeight: hasEvent ? FontWeight.bold : FontWeight.normal
                    ),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasEvent)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8, 
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControl() {
    final player = _gameManager.player;
    final playerName = player['name'] ?? 'Player';
    final playerStatus = player['status'] ?? '正常';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), offset: const Offset(0, -2), blurRadius: 10)
        ]
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 左侧：主角信息 (可点击查看详情)
            Expanded(
              child: InkWell(
                onTap: _showPlayerDetail,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.blueGrey.shade800,
                        child: Text(
                          playerName.isNotEmpty ? playerName[0] : 'P', 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              playerName, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              playerStatus, 
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white10),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
            
            // 右侧：结束今天按钮
            ElevatedButton.icon(
              onPressed: _isSettling ? null : () => _triggerTurnSettlement(false),
              icon: const Icon(Icons.bedtime, size: 18),
              label: const Text("结束今天"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
              ),
            ),
          ],
        ),
      ),
    );
  }
}