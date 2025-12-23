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
    // 移除：不再检查断点续传
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
                    final preview = dialogues.isNotEmpty ? dialogues.first['message'] : '未知事件';
                    
                    return ListTile(
                      leading: const Icon(Icons.priority_high, color: Colors.amber),
                      title: const Text('突发事件', style: TextStyle(color: Colors.white)),
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
    // 每次都重新开始，不处理 Resume
    await _gameManager.startEvent(event);
    setState(() {
      _currentPlayingEvent = event;
    });
  }

  Future<void> _onEventFinished() async {
    if (_currentPlayingEvent != null) {
      await _gameManager.completeEvent(_currentPlayingEvent!);
      if (mounted) {
        setState(() {
          _currentPlayingEvent = null;
        });
      }
    }
  }

  Future<void> _onEventExit() async {
    // 直接退出，不保存进度
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
          builder: (context, scrollController) => Column(
            children: [
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
                        String latestMemory = '';
                        if (char['memory'] is List && (char['memory'] as List).isNotEmpty) {
                          latestMemory = (char['memory'] as List).last['content'] ?? '';
                        }

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
                                padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (char['identity'] != null) ...[
                                      Text('身份: ${char['identity']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                      const SizedBox(height: 4),
                                    ],
                                    if (char['personality'] != null) ...[
                                      Text('性格: ${char['personality']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                      const SizedBox(height: 8),
                                    ],
                                    if (latestMemory.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
                                        child: Text('最新记忆: $latestMemory', style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                                      ),
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

  // --- UI 构建 ---

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
              content: const Text('退出后当前事件进度将丢失。', style: TextStyle(color: Colors.white70)),
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
                onFinished: _onEventFinished,
                onExit: _onEventExit,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final day = _gameManager.day;
    final week = _gameManager.week;
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
                Text("DAY $day", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                if (eventStats['total']! > 0)
                  Text("${eventStats['total']} 个事件待触发", style: TextStyle(color: Colors.amber.withOpacity(0.7), fontSize: 10)),
              ],
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.groups, color: Colors.purpleAccent), onPressed: _showAiCharacterList), 
              IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: () {}),
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
    
    final itemWidth = (MediaQuery.of(context).size.width - 44) / 2;
    final isTemporary = scene['is_temporary'] == true;

    return GestureDetector(
      onTap: () => _onSceneTap(scene),
      child: Container(
        width: itemWidth,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: hasEvent 
              ? Border.all(color: isTemporary ? Colors.cyan.withOpacity(0.6) : Colors.amber.withOpacity(0.6), width: 1.5)
              : Border.all(color: Colors.white10),
          gradient: hasEvent ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF252525), isTemporary ? Colors.cyan.withOpacity(0.15) : Colors.amber.withOpacity(0.1)]) : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(hasEvent ? (isTemporary ? Icons.crisis_alert : Icons.location_on) : Icons.location_on_outlined, color: hasEvent ? (isTemporary ? Colors.cyanAccent : Colors.amber) : Colors.white24),
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