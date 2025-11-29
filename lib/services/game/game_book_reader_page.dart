// lib/ui/game/game_book_reader_page.dart

import 'package:flutter/material.dart';
import '../../models/bookshelf_entry.dart';
import 'game_manager.dart';

class GameBookReaderPage extends StatefulWidget {
  final BookshelfEntry entry;
  const GameBookReaderPage({super.key, required this.entry});

  @override
  State<GameBookReaderPage> createState() => _GameBookReaderPageState();
}

class _GameBookReaderPageState extends State<GameBookReaderPage> {
  late GameManager _gameManager;
  bool _isLoading = true;
  bool _isSettling = false; // 是否正在进行回合结算

  @override
  void initState() {
    super.initState();
    _gameManager = GameManager(widget.entry);
    _initGame();
  }

  Future<void> _initGame() async {
    await _gameManager.loadGameData();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // --- 逻辑操作 ---

  void _triggerTurnSettlement(bool isNextWeek) async {
    setState(() => _isSettling = true);
    
    try {
      final summary = await _gameManager.processTurnSettlement(isNextWeek: isNextWeek);
      
      if (mounted) {
        // 显示结算报告
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('时之流逝'),
            content: Text(summary),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('开始新的一天'),
              )
            ],
          ),
        );
        setState(() {}); // 刷新界面显示新数据
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('结算失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  void _onEventTap(Map<String, dynamic> event) {
    // 显示对话/事件详情
    showDialog(
      context: context,
      builder: (context) {
        final dialogues = (event['dialogues'] as List).cast<Map<String, dynamic>>();
        return AlertDialog(
          title: const Text('事件触发'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: dialogues.length,
              separatorBuilder: (c, i) => const Divider(),
              itemBuilder: (context, index) {
                final d = dialogues[index];
                return ListTile(
                  title: Text(d['name'] ?? '未知', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(d['message'] ?? ''),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('离开'),
            ),
            FilledButton(
              onPressed: () async {
                // 触发完毕，移除事件
                await _gameManager.removeEvent(event);
                Navigator.pop(context);
                setState(() {});
              },
              child: const Text('完成事件'),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 只有当有数据时才渲染
    final scene = _gameManager.getCurrentScene();
    final events = _gameManager.getCurrentSceneEvents();

    return Stack(
      children: [
        Scaffold(
          // 背景图 (可选，这里用纯色代替)
          backgroundColor: Colors.grey.shade900,
          body: SafeArea(
            child: Column(
              children: [
                // === 顶部区域 (Top) ===
                _buildTopBar(),

                // === 中间区域 (Center - Scene & Events) ===
                Expanded(
                  child: Row(
                    children: [
                      // 左侧：场景列表快速导航 (可选，这里简化为空白或场景图)
                      const Spacer(flex: 1),
                      
                      // 中间核心：场景描述 + 事件列表
                      Expanded(
                        flex: 6,
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                scene?['name'] ?? '未知领域',
                                style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                scene?['description'] ?? '这里一片荒芜，什么都没有。',
                                style: const TextStyle(fontSize: 16, color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              if (events.isEmpty)
                                const Text('(当前场景暂无事件)', style: TextStyle(color: Colors.white30))
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.center,
                                  children: events.map((e) => ActionChip(
                                    avatar: const Icon(Icons.event_available, size: 16),
                                    label: const Text('查看事件'),
                                    onPressed: () => _onEventTap(e),
                                  )).toList(),
                                )
                            ],
                          ),
                        ),
                      ),
                      
                      const Spacer(flex: 1),
                    ],
                  ),
                ),

                // === 底部区域 (Bottom) ===
                _buildBottomBar(),
              ],
            ),
          ),
        ),

        // === 结算遮罩层 ===
        if (_isSettling)
          Container(
            color: Colors.black87,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text(
                    '世界正在演变...',
                    style: TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
                  ),
                  SizedBox(height: 8),
                  Text('命运AI正在编织新的因果', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    final day = _gameManager.gameState['day'] ?? 1;
    final week = _gameManager.gameState['week'] ?? 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左上角：时间信息
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('第 $week 周', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Day $day', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          
          // 右上角：功能按钮
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.people_alt, color: Colors.white),
                tooltip: 'AI角色信息',
                onPressed: _showAiCharacterList,
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                tooltip: '设置',
                onPressed: () {}, // 暂时留空
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                tooltip: '退出',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final p = _gameManager.player;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 左下角：玩家信息
          Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blueGrey,
                  child: Text((p['name'] ?? 'P')[0], style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p['name'] ?? '玩家', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('${p['status'] ?? '正常'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('装备: ${p['equipment'] ?? '无'}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),

          // 右下角：回合推进按钮
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isSettling ? null : () => _triggerTurnSettlement(false),
                icon: const Icon(Icons.bedtime),
                label: const Text('进入下一天'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isSettling ? null : () => _triggerTurnSettlement(true),
                icon: const Icon(Icons.calendar_month),
                label: const Text('进入下一周'),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _showAiCharacterList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('AI 角色动态', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _gameManager.aiCharacters.length,
                itemBuilder: (context, index) {
                  final char = _gameManager.aiCharacters[index];
                  return ListTile(
                    leading: const Icon(Icons.person, color: Colors.white70),
                    title: Text(char['name'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text(char['status'] ?? '', style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.info_outline, color: Colors.white30),
                    onTap: () {
                      // 显示更详细的角色信息
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}