//lib/ui/reader/game_book/game_book_reader_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../models/bookshelf_entry.dart';
import '../../../../services/game/game_manager.dart';

// 引入同级目录下的组件
import 'galgame_player_overlay.dart';
import 'components/game_bars.dart';
import 'components/world_map_view.dart';
import 'components/player_profile_sheet.dart';
import 'components/character_list_sheet.dart';
import 'dialogs/game_menu_dialogs.dart';

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

  // --- 逻辑交互区 ---

  /// 触发回合结算
  void _triggerTurnSettlement(bool isNextWeek) async {
    setState(() => _isSettling = true);
    try {
      final summary = await _gameManager.processTurnSettlement(isNextWeek: isNextWeek);
      if (mounted) {
        // 调用弹窗组件显示结算结果
        await GameMenuDialogs.showSettlementDialog(context, summary);
        setState(() {}); // 刷新页面数据
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误: $e')));
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  /// 点击场景
  void _onSceneTap(Map<String, dynamic> scene) {
    GameMenuDialogs.showSceneEventsSheet(
      context: context,
      scene: scene,
      gameManager: _gameManager,
      onPlayEvent: _playEvent,
    );
  }

  /// 开始播放事件
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
                // 1. 顶部栏
                GameTopBar(
                  gameManager: _gameManager,
                  onBackTap: () => Navigator.pop(context),
                  onSettingsTap: () {
                    GameMenuDialogs.showSettingsPanel(context, _gameManager);
                  },
                ),
                
                // 2. 世界地图 (主体)
                Expanded(
                  child: WorldMapView(
                    gameManager: _gameManager,
                    onSceneTap: _onSceneTap,
                  ),
                ),
                
                // 3. 底部控制栏
                GameBottomBar(
                  gameManager: _gameManager,
                  onPlayerTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => PlayerProfileSheet(gameManager: _gameManager),
                    );
                  },
                  onCharactersTap: () {
                     showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF151515),
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (context) => CharacterListSheet(gameManager: _gameManager),
                    );
                  },
                  onSettlementTap: _isSettling ? null : () => _triggerTurnSettlement(false),
                ),
              ],
            ),

            // 4. 结算 Loading 遮罩
            if (_isSettling)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text("世界线变动中...", style: TextStyle(color: Colors.white, letterSpacing: 2))
                    ]
                  )
                ),
              ),
            
            // 5. 播放器 Overlay
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
}